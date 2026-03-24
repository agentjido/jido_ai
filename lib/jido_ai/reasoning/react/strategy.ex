defmodule Jido.AI.Reasoning.ReAct.Strategy do
  @moduledoc """
  ReAct strategy delegated to an internal per-parent worker agent.

  The parent strategy remains the public orchestration boundary (`ask/await/ask_sync`),
  while runtime execution is delegated to a lazily spawned child worker tagged
  `:react_worker`.

  ## Delegation Model

  1. Parent receives `"ai.react.query"` and prepares runtime config/context.
  2. Parent lazily spawns internal worker on first request (if needed).
  3. Parent emits `"ai.react.worker.start"` to worker.
  4. Worker streams `Jido.AI.Reasoning.ReAct` events and emits `"ai.react.worker.event"` to parent.
  5. Parent applies runtime events to parent state and emits external lifecycle/LLM/tool signals.

  ## Worker Lifecycle

  - Child tag is fixed as `:react_worker`.
  - Single active run is enforced (`:reject` busy policy).
  - Worker crash during active request marks the request failed.
  - No machine-driven fallback path is retained.

  ## Trace Retention

  Parent stores per-request runtime event history in `request_traces` with a hard cap:

      %{request_id => %{events: [event, ...], truncated?: boolean()}}

  Once 2000 events are stored for a request, `truncated?` is set to `true`
  and new events are not appended.
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Directive, as: AgentDirective
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Directive
  alias Jido.AI.Effects
  alias Jido.AI.Reasoning.ReAct.RequestTransformer
  alias Jido.AI.Reasoning.ReAct.State, as: ReActState
  alias Jido.AI.Reasoning.ReAct.Config, as: ReActRuntimeConfig
  alias Jido.AI.Reasoning.ReAct.ToolSelection
  alias Jido.AI.Signal
  alias Jido.AI.Reasoning.Helpers
  alias Jido.AI.Context, as: AIContext
  alias Jido.AI.ToolAdapter
  alias Jido.AI.Turn
  alias Jido.Thread
  alias Jido.Thread.Agent, as: ThreadAgent

  @type config :: %{
          tools: [module()],
          reqllm_tools: [ReqLLM.Tool.t()],
          actions_by_name: %{String.t() => module()},
          request_transformer: module() | nil,
          system_prompt: String.t(),
          model: String.t(),
          max_iterations: pos_integer(),
          max_tokens: pos_integer(),
          streaming: boolean(),
          base_tool_context: map(),
          base_req_http_options: list(),
          base_llm_opts: keyword(),
          provider_opt_keys_by_string: %{optional(String.t()) => atom()},
          request_policy: :reject,
          stream_timeout_ms: non_neg_integer(),
          stream_receive_timeout_ms: pos_integer(),
          stream_timeout_ms: non_neg_integer(),
          stream_receive_timeout_ms: pos_integer(),
          tool_timeout_ms: pos_integer(),
          tool_max_retries: non_neg_integer(),
          tool_retry_backoff_ms: non_neg_integer(),
          effect_policy: map(),
          observability: map(),
          runtime_adapter: true,
          runtime_task_supervisor: pid() | atom() | nil,
          agent_id: String.t() | nil
        }

  @default_model :fast
  @default_max_iterations 10
  @default_max_tokens 4_096
  @request_trace_cap 2000
  @applied_context_ops_cap 128
  @default_context_ref "default"
  @worker_tag :react_worker
  @source "/ai/react/strategy"
  @reqllm_generation_opt_keys_by_string ReqLLM.Provider.Options.all_generation_keys()
                                        |> Enum.map(&{Atom.to_string(&1), &1})
                                        |> Map.new()

  @default_system_prompt """
  You are a helpful AI assistant using the ReAct (Reason-Act) pattern.
  When you need to perform an action, use the available tools.
  When you have enough information to answer, provide your final answer directly.
  Think step by step and explain your reasoning.
  """

  @start :ai_react_start
  @llm_result :ai_react_llm_result
  @tool_result :ai_react_tool_result
  @llm_partial :ai_react_llm_partial
  @cancel :ai_react_cancel
  @request_error :ai_react_request_error
  @register_tool :ai_react_register_tool
  @unregister_tool :ai_react_unregister_tool
  @set_tool_context :ai_react_set_tool_context
  @set_system_prompt :ai_react_set_system_prompt
  @context_modify :ai_react_context_modify
  @runtime_event :ai_react_runtime_event
  @worker_event :ai_react_worker_event
  @worker_child_started :ai_react_worker_child_started
  @worker_child_exit :ai_react_worker_child_exit

  @doc "Returns the action atom for starting a ReAct conversation."
  @spec start_action() :: :ai_react_start
  def start_action, do: @start

  @doc "Returns the legacy action atom for handling LLM results (no-op in delegated mode)."
  @spec llm_result_action() :: :ai_react_llm_result
  def llm_result_action, do: @llm_result

  @doc "Returns the action atom for registering a tool dynamically."
  @spec register_tool_action() :: :ai_react_register_tool
  def register_tool_action, do: @register_tool

  @doc "Returns the action atom for unregistering a tool."
  @spec unregister_tool_action() :: :ai_react_unregister_tool
  def unregister_tool_action, do: @unregister_tool

  @doc "Returns the legacy action atom for handling tool results (no-op in delegated mode)."
  @spec tool_result_action() :: :ai_react_tool_result
  def tool_result_action, do: @tool_result

  @doc "Returns the legacy action atom for handling streaming deltas (no-op in delegated mode)."
  @spec llm_partial_action() :: :ai_react_llm_partial
  def llm_partial_action, do: @llm_partial

  @doc "Returns the action atom for request cancellation."
  @spec cancel_action() :: :ai_react_cancel
  def cancel_action, do: @cancel

  @doc "Returns the action atom for handling request rejections."
  @spec request_error_action() :: :ai_react_request_error
  def request_error_action, do: @request_error

  @doc "Returns the action atom for updating tool context."
  @spec set_tool_context_action() :: :ai_react_set_tool_context
  def set_tool_context_action, do: @set_tool_context

  @doc "Returns the action atom for updating the base system prompt."
  @spec set_system_prompt_action() :: :ai_react_set_system_prompt
  def set_system_prompt_action, do: @set_system_prompt

  @doc "Returns the canonical action atom for context lifecycle operations."
  @spec context_modify_action() :: :ai_react_context_modify
  def context_modify_action, do: @context_modify

  @doc "Returns the legacy action atom for direct runtime stream events (no-op in delegated mode)."
  @spec runtime_event_action() :: :ai_react_runtime_event
  def runtime_event_action, do: @runtime_event

  @action_specs %{
    @start => %{
      schema:
        Zoi.object(%{
          query: Zoi.string(),
          request_id: Zoi.string() |> Zoi.optional(),
          tool_context: Zoi.map() |> Zoi.optional(),
          tools: Zoi.any() |> Zoi.optional(),
          allowed_tools: Zoi.list(Zoi.string()) |> Zoi.optional(),
          request_transformer: Zoi.atom() |> Zoi.optional(),
          stream_receive_timeout_ms: Zoi.integer() |> Zoi.optional(),
          stream_timeout_ms: Zoi.integer() |> Zoi.optional(),
          req_http_options: Zoi.list(Zoi.any()) |> Zoi.optional(),
          llm_opts: Zoi.any() |> Zoi.optional(),
          extra_refs: Zoi.map() |> Zoi.optional()
        }),
      doc: "Start a delegated ReAct conversation with a user query",
      name: "ai.react.start"
    },
    @cancel => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string() |> Zoi.optional(),
          reason: Zoi.atom() |> Zoi.default(:user_cancelled)
        }),
      doc: "Cancel an in-flight ReAct request",
      name: "ai.react.cancel"
    },
    @request_error => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string(),
          reason: Zoi.atom(),
          message: Zoi.string()
        }),
      doc: "Handle request rejection event",
      name: "ai.react.request_error"
    },
    @register_tool => %{
      schema: Zoi.object(%{tool_module: Zoi.atom()}),
      doc: "Register a new tool dynamically at runtime",
      name: "ai.react.register_tool"
    },
    @unregister_tool => %{
      schema: Zoi.object(%{tool_name: Zoi.string()}),
      doc: "Unregister a tool by name",
      name: "ai.react.unregister_tool"
    },
    @set_tool_context => %{
      schema: Zoi.object(%{tool_context: Zoi.map()}),
      doc: "Update the persistent base tool context",
      name: "ai.react.set_tool_context"
    },
    @set_system_prompt => %{
      schema: Zoi.object(%{system_prompt: Zoi.string()}),
      doc: "Update the persistent base system prompt",
      name: "ai.react.set_system_prompt"
    },
    @context_modify => %{
      schema:
        Zoi.object(%{
          op_id: Zoi.string() |> Zoi.optional(),
          context_ref: Zoi.string() |> Zoi.optional(),
          operation: Zoi.map()
        }),
      doc: "Modify context lifecycle using canonical operation envelopes",
      name: "ai.react.context.modify"
    },
    @worker_event => %{
      schema: Zoi.object(%{request_id: Zoi.string(), event: Zoi.map()}),
      doc: "Handle delegated ReAct runtime event envelopes",
      name: "ai.react.worker.event"
    },
    @worker_child_started => %{
      schema:
        Zoi.object(%{
          parent_id: Zoi.string() |> Zoi.optional(),
          child_id: Zoi.string() |> Zoi.optional(),
          child_module: Zoi.any() |> Zoi.optional(),
          tag: Zoi.any(),
          pid: Zoi.any(),
          meta: Zoi.map() |> Zoi.default(%{})
        }),
      doc: "Handle worker child started lifecycle signal",
      name: "jido.agent.child.started"
    },
    @worker_child_exit => %{
      schema:
        Zoi.object(%{
          tag: Zoi.any(),
          pid: Zoi.any(),
          reason: Zoi.any()
        }),
      doc: "Handle worker child exit lifecycle signal",
      name: "jido.agent.child.exit"
    },
    # Legacy compatibility actions kept as no-op adapters.
    @llm_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), result: Zoi.any()}),
      doc: "Legacy no-op in delegated ReAct mode",
      name: "ai.react.llm_result"
    },
    @tool_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), tool_name: Zoi.string(), result: Zoi.any()}),
      doc: "Legacy no-op in delegated ReAct mode",
      name: "ai.react.tool_result"
    },
    @llm_partial => %{
      schema:
        Zoi.object(%{
          call_id: Zoi.string(),
          delta: Zoi.string(),
          chunk_type: Zoi.atom() |> Zoi.default(:content)
        }),
      doc: "Legacy no-op in delegated ReAct mode",
      name: "ai.react.llm_partial"
    },
    @runtime_event => %{
      schema: Zoi.object(%{request_id: Zoi.string(), event: Zoi.map()}),
      doc: "Legacy no-op in delegated ReAct mode",
      name: "ai.react.runtime_event"
    }
  }

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"ai.react.query", {:strategy_cmd, @start}},
      {"ai.react.cancel", {:strategy_cmd, @cancel}},
      {"ai.request.error", {:strategy_cmd, @request_error}},
      {"ai.react.register_tool", {:strategy_cmd, @register_tool}},
      {"ai.react.unregister_tool", {:strategy_cmd, @unregister_tool}},
      {"ai.react.set_tool_context", {:strategy_cmd, @set_tool_context}},
      {"ai.react.set_system_prompt", {:strategy_cmd, @set_system_prompt}},
      {"ai.react.context.modify", {:strategy_cmd, @context_modify}},
      {"ai.react.worker.event", {:strategy_cmd, @worker_event}},
      {"jido.agent.child.started", {:strategy_cmd, @worker_child_started}},
      {"jido.agent.child.exit", {:strategy_cmd, @worker_child_exit}},
      {"ai.llm.delta", Jido.Actions.Control.Noop},
      {"ai.llm.response", Jido.Actions.Control.Noop},
      {"ai.tool.result", Jido.Actions.Control.Noop},
      {"ai.request.started", Jido.Actions.Control.Noop},
      {"ai.request.completed", Jido.Actions.Control.Noop},
      {"ai.request.failed", Jido.Actions.Control.Noop},
      {"ai.usage", Jido.Actions.Control.Noop}
    ]
  end

  @impl true
  def snapshot(%Agent{} = agent, _ctx) do
    state = StratState.get(agent, %{})
    status = snapshot_status(state[:status])
    config = state[:config] || %{}

    %Jido.Agent.Strategy.Snapshot{
      status: status,
      done?: status in [:success, :failure],
      result: state[:result],
      details: build_snapshot_details(state, config)
    }
  end

  defp snapshot_status(:completed), do: :success
  defp snapshot_status(:error), do: :failure
  defp snapshot_status(:idle), do: :idle
  defp snapshot_status(_), do: :running

  defp build_snapshot_details(state, config) do
    conversation = state |> snapshot_context(config) |> AIContext.to_messages()

    trace_summary =
      state
      |> Map.get(:request_traces, %{})
      |> Enum.map(fn {request_id, trace} ->
        {request_id, %{events: length(trace.events), truncated?: trace.truncated?}}
      end)
      |> Map.new()

    %{
      phase: state[:status],
      iteration: state[:iteration],
      termination_reason: state[:termination_reason],
      streaming_text: state[:streaming_text],
      streaming_thinking: state[:streaming_thinking],
      thinking_trace: state[:thinking_trace],
      usage: state[:usage],
      duration_ms: calculate_duration(state[:started_at]),
      tool_calls: format_tool_calls(state[:pending_tool_calls] || []),
      current_llm_call_id: state[:current_llm_call_id],
      active_request_id: state[:active_request_id],
      checkpoint_token: state[:checkpoint_token],
      cancel_reason: state[:cancel_reason],
      worker_pid: state[:react_worker_pid],
      worker_status: state[:react_worker_status],
      trace_summary: trace_summary,
      model: config[:model],
      request_transformer:
        case config[:request_transformer] do
          module when is_atom(module) -> Atom.to_string(module)
          _ -> nil
        end,
      max_iterations: config[:max_iterations],
      max_tokens: config[:max_tokens],
      streaming: config[:streaming],
      stream_receive_timeout_ms: config[:stream_receive_timeout_ms],
      request_policy: config[:request_policy],
      runtime_adapter: true,
      tool_timeout_ms: config[:tool_timeout_ms],
      tool_max_retries: config[:tool_max_retries],
      tool_retry_backoff_ms: config[:tool_retry_backoff_ms],
      available_tools: Enum.map(Map.get(config, :tools, []), & &1.name()),
      conversation: conversation
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" or v == %{} or v == [] end)
    |> Map.new()
  end

  defp calculate_duration(nil), do: nil
  defp calculate_duration(started_at), do: System.monotonic_time(:millisecond) - started_at

  defp format_tool_calls([]), do: []

  defp format_tool_calls(pending_tool_calls) do
    Enum.map(pending_tool_calls, fn tc ->
      %{
        id: tc.id,
        name: tc.name,
        arguments: tc.arguments,
        status: if(tc.result == nil, do: :running, else: :completed),
        result: tc.result
      }
    end)
  end

  @impl true
  def init(%Agent{} = agent, ctx) do
    config = build_config(agent, ctx)
    active_context_ref = initial_active_context_ref(agent)
    base_context = initial_context(agent, config)
    projected_context = project_context_from_core_thread(agent, active_context_ref, base_context)
    projection_cursor_seq = core_thread_last_seq(agent)

    state =
      %{
        status: :idle,
        iteration: 0,
        context: projected_context,
        run_context: nil,
        active_context_ref: active_context_ref,
        pending_tool_calls: [],
        final_answer: nil,
        result: nil,
        current_llm_call_id: nil,
        termination_reason: nil,
        run_tool_context: %{},
        run_req_http_options: [],
        run_llm_opts: [],
        active_request_id: nil,
        cancel_reason: nil,
        usage: %{},
        started_at: nil,
        streaming_text: "",
        streaming_thinking: "",
        thinking_trace: [],
        checkpoint_token: nil,
        pending_context_op: nil,
        applied_context_ops: [],
        projection_cursor_seq: projection_cursor_seq,
        request_traces: %{},
        react_worker_pid: nil,
        react_worker_status: :missing,
        pending_worker_start: nil,
        agent_id: Map.get(agent, :id)
      }
      |> Helpers.apply_to_state([Helpers.update_config(config)])

    agent = put_strategy_state(agent, state)
    {agent, []}
  end

  @impl true
  def cmd(%Agent{} = agent, instructions, ctx) do
    {agent, directives_rev} =
      Enum.reduce(instructions, {agent, []}, fn instruction, {acc_agent, acc_directives} ->
        case process_instruction(acc_agent, instruction, ctx) do
          {new_agent, new_directives} ->
            {new_agent, Enum.reverse(new_directives, acc_directives)}

          :noop ->
            {acc_agent, acc_directives}
        end
      end)

    {agent, Enum.reverse(directives_rev)}
  end

  defp process_instruction(
         agent,
         %Jido.Instruction{action: action, params: params} = instruction,
         ctx
       ) do
    case normalize_action(action) do
      @start ->
        state = StratState.get(agent, %{})
        config = state[:config] || %{}
        provider_opt_keys_by_string = config[:provider_opt_keys_by_string] || %{}
        run_tool_context = Map.get(params, :tool_context) || %{}

        run_req_http_options =
          params |> Map.get(:req_http_options, []) |> normalize_req_http_options()

        run_llm_opts =
          params |> Map.get(:llm_opts, []) |> normalize_llm_opts(provider_opt_keys_by_string)

        agent
        |> set_run_tool_context(run_tool_context)
        |> set_run_req_http_options(run_req_http_options)
        |> set_run_llm_opts(run_llm_opts)
        |> process_start(params)

      @cancel ->
        process_cancel(agent, params)

      @request_error ->
        process_request_error(agent, params)

      @register_tool ->
        process_register_tool(agent, params)

      @unregister_tool ->
        process_unregister_tool(agent, params)

      @set_tool_context ->
        process_set_tool_context(agent, params)

      @set_system_prompt ->
        process_set_system_prompt(agent, params)

      @context_modify ->
        process_context_modify(agent, params)

      @worker_event ->
        process_worker_event(agent, params)

      @worker_child_started ->
        process_worker_child_started(agent, params)

      @worker_child_exit ->
        process_worker_child_exit(agent, params)

      # Legacy compatibility no-ops in delegated mode.
      legacy when legacy in [@llm_result, @tool_result, @llm_partial, @runtime_event] ->
        {agent, []}

      _ ->
        Helpers.maybe_execute_action_instruction(agent, instruction, ctx)
    end
  end

  defp process_start(agent, %{query: query} = params) when is_binary(query) do
    state = StratState.get(agent, %{})
    config = state[:config] || %{}
    request_id = Map.get(params, :request_id, generate_call_id())
    run_id = request_id

    if busy?(state, config) do
      directive =
        Directive.EmitRequestError.new!(%{
          request_id: request_id,
          reason: :busy,
          message: "Agent is busy (status: #{state[:status]})"
        })

      {agent, [directive]}
    else
      run_tool_context = Map.get(state, :run_tool_context, %{})
      effective_tool_context = Map.merge(config[:base_tool_context] || %{}, run_tool_context)
      run_req_http_options = Map.get(state, :run_req_http_options, [])
      base_req_http_options = normalize_req_http_options(config[:base_req_http_options])
      effective_req_http_options = base_req_http_options ++ run_req_http_options
      run_llm_opts = Map.get(state, :run_llm_opts, [])
      provider_opt_keys_by_string = config[:provider_opt_keys_by_string] || %{}
      base_llm_opts = normalize_llm_opts(config[:base_llm_opts], provider_opt_keys_by_string)
      effective_llm_opts = Keyword.merge(base_llm_opts, run_llm_opts)
      state_snapshot = normalize_map_opt(Map.get(agent, :state, %{}))

      with {:ok, effective_tools} <- resolve_request_tools(config, params),
           {:ok, request_transformer} <- resolve_request_transformer(config, params) do
        runtime_config =
          runtime_config_from_strategy(config,
            req_http_options: effective_req_http_options,
            llm_opts: effective_llm_opts,
            tools: effective_tools,
            stream_receive_timeout_ms: Map.get(params, :stream_receive_timeout_ms),
            stream_timeout_ms: Map.get(params, :stream_timeout_ms),
            request_transformer: request_transformer
          )

        base_context = strategy_context(state, config)
        extra_refs = Map.get(params, :extra_refs, %{})
        run_context = AIContext.append_user(base_context, query, refs: normalize_refs(extra_refs))
        runtime_state = runtime_state_from_context(run_context, query, request_id, run_id)
        context_ref = Map.get(state, :active_context_ref, @default_context_ref)

        {agent, state} =
          append_ai_message_event(
            agent,
            state,
            context_ref,
            %{role: :user, content: query},
            request_id,
            run_id,
            nil,
            extra_refs
          )

        worker_start_payload = %{
          request_id: request_id,
          run_id: run_id,
          query: query,
          config: runtime_config,
          state: runtime_state,
          task_supervisor: config[:runtime_task_supervisor],
          context:
            Map.merge(effective_tool_context, %{
              state: state_snapshot,
              request_id: request_id,
              run_id: run_id,
              agent_id: state[:agent_id] || Map.get(agent, :id),
              observability: config[:observability] || %{},
              effect_policy: config[:effect_policy] || Effects.default_policy()
            })
        }

        {new_state, directives} = ensure_worker_start(state, worker_start_payload)

        new_state =
          new_state
          |> Map.put(:status, :awaiting_llm)
          |> Map.put(:active_request_id, request_id)
          |> Map.put(:current_llm_call_id, nil)
          |> Map.put(:iteration, 1)
          |> Map.put(:result, nil)
          |> Map.put(:termination_reason, nil)
          |> Map.put(:started_at, System.monotonic_time(:millisecond))
          |> Map.put(:streaming_text, "")
          |> Map.put(:streaming_thinking, "")
          |> Map.put(:pending_tool_calls, [])
          |> Map.put(:cancel_reason, nil)
          |> Map.put(:checkpoint_token, nil)
          |> Map.put(:run_context, run_context)
          |> ensure_request_trace(request_id)

        {put_strategy_state(agent, new_state), directives}
      else
        {:error, reason, message} ->
          directive =
            Directive.EmitRequestError.new!(%{
              request_id: request_id,
              reason: reason,
              message: message
            })

          {agent, [directive]}
      end
    end
  end

  defp process_start(agent, _params), do: {agent, []}

  defp process_cancel(agent, params) do
    state = StratState.get(agent, %{})
    request_id = Map.get(params, :request_id, state[:active_request_id])
    reason = Map.get(params, :reason, :user_cancelled)

    should_cancel? =
      is_binary(request_id) and request_id == state[:active_request_id] and
        is_pid(state[:react_worker_pid]) and
        Process.alive?(state[:react_worker_pid])

    directives =
      if should_cancel? do
        [
          AgentDirective.emit_to_pid(
            worker_cancel_signal(request_id, reason),
            state[:react_worker_pid]
          )
        ]
      else
        []
      end

    new_state =
      if should_cancel? do
        Map.put(state, :cancel_reason, reason)
      else
        state
      end

    {put_strategy_state(agent, new_state), directives}
  end

  defp process_request_error(agent, %{request_id: request_id, reason: reason, message: message}) do
    state = StratState.get(agent, %{})

    new_state =
      Map.put(state, :last_request_error, %{
        request_id: request_id,
        reason: reason,
        message: message
      })

    {put_strategy_state(agent, new_state), []}
  end

  defp process_request_error(agent, _params), do: {agent, []}

  defp process_register_tool(agent, %{tool_module: module}) when is_atom(module) do
    state = StratState.get(agent, %{})
    config = state[:config]

    new_tools = [module | config[:tools]] |> Enum.uniq()
    new_actions_by_name = Map.put(config[:actions_by_name], module.name(), module)
    new_reqllm_tools = ToolAdapter.from_actions(new_tools)

    new_state =
      Helpers.apply_to_state(
        state,
        Helpers.update_tools_config(new_tools, new_actions_by_name, new_reqllm_tools)
      )

    {put_strategy_state(agent, new_state), []}
  end

  defp process_register_tool(agent, _params), do: {agent, []}

  defp process_unregister_tool(agent, %{tool_name: tool_name}) when is_binary(tool_name) do
    state = StratState.get(agent, %{})
    config = state[:config]

    new_tools = Enum.reject(config[:tools], fn m -> m.name() == tool_name end)
    new_actions_by_name = Map.delete(config[:actions_by_name], tool_name)
    new_reqllm_tools = ToolAdapter.from_actions(new_tools)

    new_state =
      Helpers.apply_to_state(
        state,
        Helpers.update_tools_config(new_tools, new_actions_by_name, new_reqllm_tools)
      )

    {put_strategy_state(agent, new_state), []}
  end

  defp process_unregister_tool(agent, _params), do: {agent, []}

  defp process_set_tool_context(agent, %{tool_context: new_context}) when is_map(new_context) do
    state = StratState.get(agent, %{})

    new_state =
      Helpers.apply_to_state(state, [
        Helpers.set_config_field(:base_tool_context, new_context)
      ])

    {put_strategy_state(agent, new_state), []}
  end

  defp process_set_tool_context(agent, _params), do: {agent, []}

  defp process_set_system_prompt(agent, %{system_prompt: prompt}) when is_binary(prompt) do
    state = StratState.get(agent, %{})
    run_context = Map.get(state, :run_context)
    base_context = strategy_context(state, state[:config] || %{})

    new_state =
      Helpers.apply_to_state(state, [
        Helpers.set_config_field(:system_prompt, prompt)
      ])
      |> Map.put(:context, %{base_context | system_prompt: prompt})
      |> then(fn updated ->
        if match?(%AIContext{}, run_context) do
          Map.put(updated, :run_context, %{run_context | system_prompt: prompt})
        else
          updated
        end
      end)

    {put_strategy_state(agent, new_state), []}
  end

  defp process_set_system_prompt(agent, _params), do: {agent, []}

  defp process_context_modify(agent, params) when is_map(params) do
    state = StratState.get(agent, %{})

    case normalize_context_operation(params, state) do
      {:ok, context_op} ->
        if active_run?(state) do
          {put_strategy_state(agent, Map.put(state, :pending_context_op, context_op)), []}
        else
          {agent, new_state} = apply_context_op(agent, state, context_op)
          {put_strategy_state(agent, new_state), []}
        end

      :error ->
        {agent, []}
    end
  end

  defp process_context_modify(agent, _params), do: {agent, []}

  defp initial_context(%Agent{} = agent, config) do
    state = agent.state || %{}

    case Map.fetch(state, :context) do
      {:ok, nil} ->
        AIContext.new(system_prompt: config[:system_prompt])

      {:ok, source_context} ->
        case AIContext.coerce(source_context) do
          {:ok, %AIContext{system_prompt: nil} = context} ->
            %{context | system_prompt: config[:system_prompt]}

          {:ok, %AIContext{} = context} ->
            context

          :error ->
            raise ArgumentError,
                  "invalid initial_state[:context]; expected Jido.AI.Context"
        end

      :error ->
        if legacy_thread_context?(Map.get(state, :thread)) do
          raise ArgumentError,
                "initial_state[:thread] is no longer supported for AI context; use initial_state[:context] with Jido.AI.Context"
        else
          AIContext.new(system_prompt: config[:system_prompt])
        end
    end
  end

  defp legacy_thread_context?(%{} = value) do
    has_entries_key? = Map.has_key?(value, :entries) or Map.has_key?(value, "entries")

    has_system_prompt_key? =
      Map.has_key?(value, :system_prompt) or Map.has_key?(value, "system_prompt")

    has_entries_key? and has_system_prompt_key?
  end

  defp legacy_thread_context?(_), do: false

  defp active_run?(state) do
    is_binary(state[:active_request_id]) and state[:status] in [:awaiting_llm, :awaiting_tool]
  end

  defp apply_context_op(agent, state, %{op_id: op_id} = context_op) do
    if context_op_applied?(state, op_id) do
      {agent, Map.put(state, :pending_context_op, nil)}
    else
      do_apply_context_op(agent, state, context_op)
    end
  end

  defp do_apply_context_op(agent, state, %{
         op_id: op_id,
         context_ref: context_ref,
         operation: %{type: :replace} = operation
       }) do
    context = operation.result_context

    state =
      state
      |> maybe_sync_config_prompt(context)
      |> Map.put(:context, context)
      |> Map.put(:active_context_ref, context_ref)
      |> Map.put(:pending_context_op, nil)
      |> record_applied_context_op(op_id)

    {agent, state} =
      append_ai_context_operation_event(agent, state, %{
        op_id: op_id,
        context_ref: context_ref,
        operation: operation
      })

    {agent, state}
  end

  defp do_apply_context_op(agent, state, %{
         op_id: op_id,
         context_ref: context_ref,
         operation: %{type: :switch} = operation
       }) do
    projected_context =
      project_context_from_core_thread(
        agent,
        context_ref,
        fresh_projection_context(state[:config] || %{})
      )

    state =
      state
      |> Map.put(:active_context_ref, context_ref)
      |> Map.put(:context, projected_context)
      |> Map.put(:pending_context_op, nil)
      |> record_applied_context_op(op_id)

    {agent, state} =
      append_ai_context_operation_event(agent, state, %{
        op_id: op_id,
        context_ref: context_ref,
        operation: operation
      })

    {agent, state}
  end

  defp maybe_sync_config_prompt(state, %AIContext{system_prompt: prompt})
       when is_binary(prompt) do
    Helpers.apply_to_state(state, [
      Helpers.set_config_field(:system_prompt, prompt)
    ])
  end

  defp maybe_sync_config_prompt(state, _context), do: state

  defp maybe_apply_pending_context_op(agent, state) do
    case Map.get(state, :pending_context_op) do
      %{operation: %{}} = context_op -> apply_context_op(agent, state, context_op)
      _ -> {agent, state}
    end
  end

  defp maybe_apply_pending_context_op_after_terminal(agent, state, kind)
       when kind in [:request_completed, :request_failed, :request_cancelled] do
    maybe_apply_pending_context_op(agent, state)
  end

  defp maybe_apply_pending_context_op_after_terminal(agent, state, _kind), do: {agent, state}

  defp normalize_context_operation(params, state) do
    operation = fetch_map_value(params, :operation)

    with true <- is_map(operation),
         {:ok, type} <- normalize_context_operation_type(fetch_map_value(operation, :type)),
         {:ok, reason} <- normalize_context_operation_reason(fetch_map_value(operation, :reason)),
         {:ok, context_ref} <- normalize_context_ref(params, operation, state),
         {:ok, op_id} <- normalize_context_op_id(params, operation) do
      base =
        %{
          op_id: op_id,
          context_ref: context_ref,
          operation: %{
            type: type,
            reason: reason,
            base_seq: normalize_optional_integer(fetch_map_value(operation, :base_seq)),
            meta: normalize_optional_map(fetch_map_value(operation, :meta))
          }
        }

      normalize_context_operation_payload(base, operation)
    else
      _ -> :error
    end
  end

  defp normalize_context_operation_payload(base, operation) do
    case base.operation.type do
      :replace ->
        result_payload =
          fetch_map_value(operation, :result_context) ||
            fetch_map_value(operation, :context)

        case AIContext.coerce(result_payload) do
          {:ok, context} ->
            {:ok, put_in(base, [:operation, :result_context], context)}

          :error ->
            :error
        end

      :switch ->
        {:ok, put_in(base, [:operation, :result_context], nil)}
    end
  end

  defp normalize_context_operation_type(type) when type in [:replace, :switch], do: {:ok, type}
  defp normalize_context_operation_type("replace"), do: {:ok, :replace}
  defp normalize_context_operation_type("switch"), do: {:ok, :switch}
  defp normalize_context_operation_type(_), do: :error

  defp normalize_context_operation_reason(reason)
       when reason in [:manual, :restore, :compaction, :system],
       do: {:ok, reason}

  defp normalize_context_operation_reason("manual"), do: {:ok, :manual}
  defp normalize_context_operation_reason("restore"), do: {:ok, :restore}
  defp normalize_context_operation_reason("compaction"), do: {:ok, :compaction}
  defp normalize_context_operation_reason("system"), do: {:ok, :system}
  defp normalize_context_operation_reason(nil), do: {:ok, :manual}
  defp normalize_context_operation_reason(_), do: :error

  defp normalize_context_ref(params, operation, state) do
    ref =
      fetch_map_value(params, :context_ref) ||
        fetch_map_value(operation, :context_ref) ||
        Map.get(state, :active_context_ref) ||
        @default_context_ref

    if is_binary(ref) and ref != "", do: {:ok, ref}, else: :error
  end

  defp normalize_context_op_id(params, operation) do
    op_id =
      fetch_map_value(params, :op_id) ||
        fetch_map_value(operation, :op_id) ||
        fetch_map_value(params, :signal_id) ||
        "op_#{Jido.Util.generate_id()}"

    if is_binary(op_id) and op_id != "", do: {:ok, op_id}, else: :error
  end

  defp context_op_applied?(state, op_id) when is_binary(op_id) do
    op_id in Map.get(state, :applied_context_ops, [])
  end

  defp context_op_applied?(_state, _op_id), do: false

  defp record_applied_context_op(state, op_id) when is_binary(op_id) do
    existing = Map.get(state, :applied_context_ops, [])

    updated =
      [op_id | Enum.reject(existing, &(&1 == op_id))] |> Enum.take(@applied_context_ops_cap)

    Map.put(state, :applied_context_ops, updated)
  end

  defp record_applied_context_op(state, _op_id), do: state

  defp maybe_append_ai_message_event_from_runtime(agent, state, event) do
    context_ref = Map.get(state, :active_context_ref, @default_context_ref)
    request_id = event_field(event, :request_id, state[:active_request_id])
    run_id = event_field(event, :run_id, request_id)
    signal_id = event_field(event, :id)
    data = event_field(event, :data, %{})

    case event_kind(event) do
      :llm_completed ->
        turn_type = event_field(data, :turn_type, :final_answer)
        text = event_field(data, :text, "")
        tool_calls = event_field(data, :tool_calls, [])
        thinking = event_field(data, :thinking_content)
        assistant_tool_calls = if turn_type == :tool_calls, do: tool_calls, else: nil

        append_ai_message_event(
          agent,
          state,
          context_ref,
          %{
            role: :assistant,
            content: text,
            tool_calls: assistant_tool_calls,
            thinking: thinking
          },
          request_id,
          run_id,
          signal_id
        )

      :tool_completed ->
        tool_call_id = event_field(data, :tool_call_id, event_field(event, :tool_call_id, ""))
        tool_name = event_field(data, :tool_name, event_field(event, :tool_name, ""))
        tool_result = normalize_tool_result(event_field(data, :result, {:error, :unknown, []}))
        content = Turn.format_tool_result_content(tool_result)

        append_ai_message_event(
          agent,
          state,
          context_ref,
          %{role: :tool, content: content, tool_call_id: tool_call_id, name: tool_name},
          request_id,
          run_id,
          signal_id
        )

      _ ->
        {agent, state}
    end
  end

  defp append_ai_message_event(
         agent,
         state,
         context_ref,
         %{} = message,
         request_id,
         run_id,
         signal_id,
         extra_refs \\ %{}
       ) do
    payload =
      message
      |> Map.put(:context_ref, context_ref)
      |> Map.put(:request_id, request_id)
      |> Map.put(:run_id, run_id)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    refs =
      extra_refs
      |> sanitize_extra_refs()
      |> Map.merge(%{
        request_id: request_id,
        run_id: run_id
      })
      |> maybe_put_ref(:signal_id, signal_id)

    append_core_thread_entry(agent, state, :ai_message, payload, refs)
  end

  defp append_ai_context_operation_event(agent, state, %{
         op_id: op_id,
         context_ref: context_ref,
         operation: operation
       }) do
    serialized_operation =
      operation
      |> Map.update(:result_context, nil, fn
        %AIContext{} = context -> serialize_context(context)
        other -> other
      end)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    payload = %{
      op_id: op_id,
      context_ref: context_ref,
      operation: serialized_operation
    }

    refs = %{op_id: op_id, context_ref: context_ref}

    append_core_thread_entry(agent, state, :ai_context_operation, payload, refs)
  end

  defp append_core_thread_entry(agent, state, kind, payload, refs)
       when is_map(payload) and is_map(refs) do
    agent =
      ThreadAgent.append(agent, %{
        kind: kind,
        payload: payload,
        refs: refs
      })

    {agent, Map.put(state, :projection_cursor_seq, core_thread_last_seq(agent))}
  end

  defp project_context_from_core_thread(agent, context_ref, %AIContext{} = fallback_context) do
    case ThreadAgent.get(agent) do
      %Thread{} = thread ->
        project_context_from_entries(Thread.to_list(thread), context_ref, fallback_context)

      _ ->
        fallback_context
    end
  end

  defp project_context_from_entries(entries, context_ref, %AIContext{} = fallback_context)
       when is_list(entries) do
    {anchor_context, anchor_seq} =
      Enum.reduce(entries, {fallback_context, -1}, fn entry, {current_context, current_anchor_seq} ->
        with :ai_context_operation <- fetch_map_value(entry, :kind),
             payload when is_map(payload) <- fetch_map_value(entry, :payload),
             ^context_ref <- fetch_map_value(payload, :context_ref),
             operation when is_map(operation) <- fetch_map_value(payload, :operation),
             :replace <- normalize_operation_type(fetch_map_value(operation, :type)),
             {:ok, context} <- AIContext.coerce(fetch_map_value(operation, :result_context)) do
          {context, fetch_map_value(entry, :seq) || current_anchor_seq}
        else
          _ -> {current_context, current_anchor_seq}
        end
      end)

    Enum.reduce(entries, anchor_context, fn entry, acc ->
      seq = fetch_map_value(entry, :seq) || -1

      with true <- seq > anchor_seq,
           :ai_message <- fetch_map_value(entry, :kind),
           payload when is_map(payload) <- fetch_map_value(entry, :payload),
           ^context_ref <- fetch_map_value(payload, :context_ref) do
        refs = fetch_map_value(entry, :refs)
        apply_projected_ai_message(acc, payload, refs)
      else
        _ -> acc
      end
    end)
  end

  defp apply_projected_ai_message(%AIContext{} = context, payload, refs) do
    case normalize_message_role(fetch_map_value(payload, :role)) do
      :user ->
        case fetch_map_value(payload, :content) do
          content when is_binary(content) ->
            AIContext.append_user(context, content, refs: normalize_refs(refs))

          _ ->
            context
        end

      :assistant ->
        content = fetch_map_value(payload, :content)
        tool_calls = fetch_map_value(payload, :tool_calls)
        thinking = fetch_map_value(payload, :thinking)
        opts = if is_binary(thinking) and thinking != "", do: [thinking: thinking], else: []
        opts = Keyword.put(opts, :refs, normalize_refs(refs))

        AIContext.append_assistant(
          context,
          normalize_content(content),
          normalize_optional_list(tool_calls),
          opts
        )

      :tool ->
        case {fetch_map_value(payload, :tool_call_id), fetch_map_value(payload, :name)} do
          {tool_call_id, name} when is_binary(tool_call_id) and is_binary(name) ->
            AIContext.append_tool_result(
              context,
              tool_call_id,
              name,
              normalize_content(fetch_map_value(payload, :content)),
              refs: normalize_refs(refs)
            )

          _ ->
            context
        end

      _ ->
        context
    end
  end

  defp normalize_message_role(role) when role in [:user, :assistant, :tool], do: role
  defp normalize_message_role("user"), do: :user
  defp normalize_message_role("assistant"), do: :assistant
  defp normalize_message_role("tool"), do: :tool
  defp normalize_message_role(_), do: :unknown

  defp normalize_operation_type(type) when type in [:replace, :switch], do: type
  defp normalize_operation_type("replace"), do: :replace
  defp normalize_operation_type("switch"), do: :switch
  defp normalize_operation_type(_), do: :unknown

  defp serialize_context(%AIContext{} = context) do
    %{
      id: context.id,
      system_prompt: context.system_prompt,
      entries: Enum.map(context.entries, &Map.from_struct/1)
    }
  end

  defp initial_active_context_ref(%Agent{state: state}) when is_map(state) do
    case Map.get(state, :active_context_ref) do
      ref when is_binary(ref) and ref != "" -> ref
      _ -> @default_context_ref
    end
  end

  defp initial_active_context_ref(_), do: @default_context_ref

  defp core_thread_last_seq(%Agent{} = agent) do
    agent
    |> ThreadAgent.get()
    |> core_thread_last_seq()
  end

  defp core_thread_last_seq(%Thread{} = thread) do
    case Thread.last(thread) do
      %{seq: seq} when is_integer(seq) -> seq
      _ -> -1
    end
  end

  defp core_thread_last_seq(_), do: -1

  defp maybe_put_ref(refs, _key, nil), do: refs
  defp maybe_put_ref(refs, key, value), do: Map.put(refs, key, value)

  defp sanitize_extra_refs(extra_refs) when is_map(extra_refs) do
    Map.drop(extra_refs, [:request_id, :run_id, :signal_id])
  end

  defp sanitize_extra_refs(_extra_refs), do: %{}

  defp fetch_map_value(%{} = map, key) when is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp fetch_map_value(_map, _key), do: nil

  defp normalize_optional_integer(value) when is_integer(value), do: value
  defp normalize_optional_integer(_), do: nil

  defp normalize_optional_map(value) when is_map(value), do: value
  defp normalize_optional_map(_), do: %{}

  defp normalize_optional_list(value) when is_list(value), do: value
  defp normalize_optional_list(_), do: nil

  defp normalize_content(value) when is_binary(value), do: value
  defp normalize_content(nil), do: ""
  defp normalize_content(value), do: inspect(value)

  defp normalize_refs(refs) when is_map(refs) and map_size(refs) > 0, do: refs
  defp normalize_refs(_), do: nil

  defp process_worker_child_started(agent, %{tag: tag, pid: pid}) when is_pid(pid) do
    state = StratState.get(agent, %{})

    if react_worker_tag?(tag) do
      pending = state[:pending_worker_start]

      base_state =
        state
        |> Map.put(:react_worker_pid, pid)
        |> Map.put(:react_worker_status, :ready)

      if is_map(pending) do
        directive = AgentDirective.emit_to_pid(worker_start_signal(pending), pid)

        new_state =
          base_state
          |> Map.put(:pending_worker_start, nil)
          |> Map.put(:react_worker_status, :running)

        {put_strategy_state(agent, new_state), [directive]}
      else
        {put_strategy_state(agent, base_state), []}
      end
    else
      {agent, []}
    end
  end

  defp process_worker_child_started(agent, _params), do: {agent, []}

  defp process_worker_child_exit(agent, %{tag: tag, pid: pid, reason: reason}) do
    state = StratState.get(agent, %{})

    if react_worker_tag?(tag) do
      tracked? = worker_pid_matches?(state[:react_worker_pid], pid)

      if tracked? do
        request_id = state[:active_request_id]

        base_state =
          state
          |> Map.put(:react_worker_pid, nil)
          |> Map.put(:react_worker_status, :missing)
          |> Map.put(:pending_worker_start, nil)

        if is_binary(request_id) and state[:status] in [:awaiting_llm, :awaiting_tool] do
          error = {:react_worker_exit, reason}

          failure_signal =
            Signal.RequestFailed.new!(%{
              request_id: request_id,
              error: error,
              run_id: request_id
            })

          Jido.AgentServer.cast(self(), failure_signal)

          failed_state =
            base_state
            |> Map.put(:status, :error)
            |> Map.put(:termination_reason, :error)
            |> Map.put(:result, inspect(error))
            |> Map.put(:active_request_id, nil)
            |> Map.put(:run_context, nil)
            |> Map.delete(:run_tool_context)
            |> Map.delete(:run_req_http_options)
            |> Map.delete(:run_llm_opts)

          {agent, failed_state} = maybe_apply_pending_context_op(agent, failed_state)

          {put_strategy_state(agent, failed_state), []}
        else
          {put_strategy_state(agent, base_state), []}
        end
      else
        {agent, []}
      end
    else
      {agent, []}
    end
  end

  defp process_worker_event(agent, %{event: event} = params) when is_map(event) do
    state = StratState.get(agent, %{})
    event = normalize_event_map(event)
    request_id = event_field(event, :request_id, params[:request_id] || state[:active_request_id])

    state = append_trace_event(state, request_id, event)
    {new_state, signals} = apply_runtime_event(state, event)
    Enum.each(signals, &Jido.AgentServer.cast(self(), &1))

    kind = event_kind(event)
    {agent, new_state} = maybe_append_ai_message_event_from_runtime(agent, new_state, event)
    {agent, new_state} = maybe_apply_pending_context_op_after_terminal(agent, new_state, kind)
    new_state = maybe_mark_worker_ready(new_state, kind)
    agent = put_strategy_state(agent, new_state)
    {agent, directives} = maybe_apply_runtime_effects(agent, event, new_state)

    {agent, directives}
  end

  defp process_worker_event(agent, _params), do: {agent, []}

  defp apply_runtime_event(state, event) do
    kind = event_kind(event)
    iteration = event_field(event, :iteration, state[:iteration] || 0)
    request_id = event_field(event, :request_id, state[:active_request_id])
    llm_call_id = event_field(event, :llm_call_id, state[:current_llm_call_id])
    data = event_field(event, :data, %{})

    base_state =
      state
      |> Map.put(:active_request_id, request_id)
      |> Map.put(:iteration, iteration)
      |> Map.put(:current_llm_call_id, llm_call_id)

    case kind do
      :request_started ->
        query = event_field(data, :query, "")

        started_state =
          base_state
          |> Map.put(:status, :awaiting_llm)
          |> Map.put(:result, nil)
          |> Map.put(:termination_reason, nil)
          |> Map.put(:started_at, event_field(event, :at_ms, System.monotonic_time(:millisecond)))
          |> Map.put(:streaming_text, "")
          |> Map.put(:streaming_thinking, "")
          |> ensure_request_trace(request_id)

        signal =
          Signal.RequestStarted.new!(%{request_id: request_id, query: query, run_id: request_id})

        {started_state, [signal]}

      :llm_started ->
        {Map.put(base_state, :status, :awaiting_llm), []}

      :llm_delta ->
        chunk_type = event_field(data, :chunk_type, :content)
        delta = event_field(data, :delta, "")

        updated =
          case chunk_type do
            :thinking ->
              Map.update(base_state, :streaming_thinking, delta, &(&1 <> delta))

            _ ->
              Map.update(base_state, :streaming_text, delta, &(&1 <> delta))
          end

        signal =
          Signal.LLMDelta.new!(%{call_id: llm_call_id || "", delta: delta, chunk_type: chunk_type})

        {updated, [signal]}

      :llm_completed ->
        turn_type = event_field(data, :turn_type, :final_answer)
        text = event_field(data, :text, "")
        thinking_content = event_field(data, :thinking_content)
        reasoning_details = event_field(data, :reasoning_details)
        tool_calls = event_field(data, :tool_calls, [])
        usage = event_field(data, :usage, %{})
        call_id = llm_call_id || event_field(data, :call_id, "")

        pending_tool_calls =
          Enum.map(tool_calls, fn tc ->
            %{
              id: event_field(tc, :id, ""),
              name: event_field(tc, :name, ""),
              arguments: event_field(tc, :arguments, %{}),
              result: nil
            }
          end)

        refs = runtime_event_refs(event, request_id)

        updated =
          base_state
          |> Map.put(:status, if(turn_type == :tool_calls, do: :awaiting_tool, else: :completed))
          |> Map.put(:pending_tool_calls, pending_tool_calls)
          |> append_assistant_to_run_context(
            turn_type,
            text,
            tool_calls,
            thinking_content,
            reasoning_details,
            refs
          )
          |> Map.update(:usage, usage || %{}, fn existing ->
            merge_usage(existing, usage || %{})
          end)
          |> maybe_append_thinking_trace(thinking_content)
          |> maybe_put_result(turn_type, text)

        llm_signal =
          Signal.LLMResponse.new!(%{
            call_id: call_id,
            result:
              {:ok,
               %{
                 type: turn_type,
                 text: text,
                 thinking_content: thinking_content,
                 reasoning_details: reasoning_details,
                 tool_calls: tool_calls,
                 usage: usage
               }, []}
          })

        usage_signal = maybe_usage_signal(call_id, config_model(state), usage)
        {updated, Enum.reject([llm_signal, usage_signal], &is_nil/1)}

      :tool_started ->
        tool_call_id = event_field(data, :tool_call_id, event_field(event, :tool_call_id, ""))
        tool_name = event_field(data, :tool_name, event_field(event, :tool_name, ""))
        arguments = event_field(data, :arguments, [])

        updated = Map.put(base_state, :status, :awaiting_tool)

        signal =
          Signal.ToolStarted.new!(%{
            call_id: tool_call_id,
            tool_name: tool_name,
            arguments: arguments
          })

        {updated, [signal]}

      :tool_completed ->
        tool_call_id = event_field(data, :tool_call_id, event_field(event, :tool_call_id, ""))
        tool_name = event_field(data, :tool_name, event_field(event, :tool_name, ""))
        tool_result = normalize_tool_result(event_field(data, :result, {:error, :unknown, []}))

        refs = runtime_event_refs(event, request_id)

        updated =
          base_state
          |> Map.update(:pending_tool_calls, [], fn pending ->
            Enum.map(pending, fn tc ->
              if tc.id == tool_call_id, do: %{tc | result: tool_result}, else: tc
            end)
          end)
          |> append_tool_result_to_run_context(tool_call_id, tool_name, tool_result, refs)

        signal =
          Signal.ToolResult.new!(%{
            call_id: tool_call_id,
            tool_name: tool_name,
            result: tool_result
          })

        {updated, [signal]}

      :request_completed ->
        result = event_field(data, :result)
        termination_reason = event_field(data, :termination_reason, :final_answer)
        usage = event_field(data, :usage, %{})

        updated =
          base_state
          |> Map.put(:status, :completed)
          |> Map.put(:result, result)
          |> Map.put(:termination_reason, termination_reason)
          |> Map.put(:usage, usage || %{})
          |> commit_run_context()
          |> Map.put(:active_request_id, nil)
          |> Map.delete(:run_tool_context)
          |> Map.delete(:run_req_http_options)
          |> Map.delete(:run_llm_opts)

        signal =
          Signal.RequestCompleted.new!(%{
            request_id: request_id,
            result: result,
            run_id: request_id
          })

        {updated, [signal]}

      :request_failed ->
        error = event_field(data, :error, :unknown_error)

        updated =
          base_state
          |> Map.put(:status, :error)
          |> Map.put(:result, inspect(error))
          |> Map.put(:termination_reason, :error)
          |> Map.put(:run_context, nil)
          |> Map.put(:active_request_id, nil)
          |> Map.delete(:run_tool_context)
          |> Map.delete(:run_req_http_options)
          |> Map.delete(:run_llm_opts)

        signal =
          Signal.RequestFailed.new!(%{request_id: request_id, error: error, run_id: request_id})

        {updated, [signal]}

      :request_cancelled ->
        reason = event_field(data, :reason, :cancelled)
        error = {:cancelled, reason}

        updated =
          base_state
          |> Map.put(:status, :error)
          |> Map.put(:result, inspect(error))
          |> Map.put(:termination_reason, :cancelled)
          |> Map.put(:cancel_reason, reason)
          |> Map.put(:run_context, nil)
          |> Map.put(:active_request_id, nil)
          |> Map.delete(:run_tool_context)
          |> Map.delete(:run_req_http_options)
          |> Map.delete(:run_llm_opts)

        signal =
          Signal.RequestFailed.new!(%{request_id: request_id, error: error, run_id: request_id})

        {updated, [signal]}

      :checkpoint ->
        token = event_field(data, :token)

        updated =
          base_state
          |> Map.put(:checkpoint_token, token)
          |> then(fn state_after_checkpoint ->
            if state[:status] in [:completed, :error] and is_nil(state[:active_request_id]) do
              Map.put(state_after_checkpoint, :active_request_id, nil)
            else
              state_after_checkpoint
            end
          end)

        {updated, []}

      _ ->
        {base_state, []}
    end
  end

  defp maybe_append_thinking_trace(state, nil), do: state
  defp maybe_append_thinking_trace(state, ""), do: state

  defp maybe_append_thinking_trace(state, thinking_content) do
    trace_entry = %{
      call_id: state[:current_llm_call_id],
      iteration: state[:iteration],
      thinking: thinking_content
    }

    Map.update(state, :thinking_trace, [trace_entry], fn trace -> trace ++ [trace_entry] end)
  end

  defp maybe_put_result(state, :final_answer, result), do: Map.put(state, :result, result)
  defp maybe_put_result(state, _turn_type, _result), do: state

  defp maybe_usage_signal(_call_id, _model, usage) when usage in [%{}, nil], do: nil

  defp maybe_usage_signal(call_id, model, usage) do
    input_tokens = Map.get(usage, :input_tokens, 0)
    output_tokens = Map.get(usage, :output_tokens, 0)

    Signal.Usage.new!(%{
      call_id: call_id,
      model: Jido.AI.ModelInput.label(model),
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: input_tokens + output_tokens
    })
  end

  defp merge_usage(existing, incoming) do
    Map.merge(existing || %{}, incoming || %{}, fn _k, left, right ->
      (left || 0) + (right || 0)
    end)
  end

  defp event_kind(event) do
    case event_field(event, :kind) do
      kind when is_atom(kind) -> kind
      kind when is_binary(kind) -> runtime_kind_from_string(kind)
      _ -> :unknown
    end
  end

  defp runtime_kind_from_string("request_started"), do: :request_started
  defp runtime_kind_from_string("llm_started"), do: :llm_started
  defp runtime_kind_from_string("llm_delta"), do: :llm_delta
  defp runtime_kind_from_string("llm_completed"), do: :llm_completed
  defp runtime_kind_from_string("tool_started"), do: :tool_started
  defp runtime_kind_from_string("tool_completed"), do: :tool_completed
  defp runtime_kind_from_string("checkpoint"), do: :checkpoint
  defp runtime_kind_from_string("request_completed"), do: :request_completed
  defp runtime_kind_from_string("request_failed"), do: :request_failed
  defp runtime_kind_from_string("request_cancelled"), do: :request_cancelled
  defp runtime_kind_from_string(_), do: :unknown

  defp event_field(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp normalize_event_map(event) when is_map(event), do: event

  defp config_model(state) do
    state
    |> Map.get(:config, %{})
    |> Map.get(:model)
  end

  defp runtime_config_from_strategy(config, opts) do
    provider_opt_keys_by_string = config[:provider_opt_keys_by_string] || %{}

    req_http_options =
      opts
      |> Keyword.get(:req_http_options, config[:base_req_http_options] || [])
      |> normalize_req_http_options()

    llm_opts =
      opts
      |> Keyword.get(:llm_opts, config[:base_llm_opts] || [])
      |> normalize_llm_opts(provider_opt_keys_by_string)

    tools = Keyword.get(opts, :tools, config[:actions_by_name] || %{})
    request_transformer = Keyword.get(opts, :request_transformer, config[:request_transformer])

    stream_timeout_ms =
      resolve_stream_timeout_ms_opt(
        opts,
        Map.get(config, :stream_timeout_ms, Map.get(config, :stream_receive_timeout_ms, 0))
      )

    runtime_opts = %{
      model: config[:model],
      system_prompt: config[:system_prompt],
      tools: tools,
      request_transformer: request_transformer,
      max_iterations: config[:max_iterations],
      max_tokens: config[:max_tokens],
      streaming: config[:streaming],
      stream_timeout_ms: stream_timeout_ms,
      req_http_options: req_http_options,
      llm_opts: llm_opts,
      tool_timeout_ms: config[:tool_timeout_ms],
      tool_max_retries: config[:tool_max_retries],
      tool_retry_backoff_ms: config[:tool_retry_backoff_ms],
      emit_telemetry?: get_in(config, [:observability, :emit_telemetry?]),
      redact_tool_args?: get_in(config, [:observability, :redact_tool_args?]),
      capture_deltas?: get_in(config, [:observability, :emit_llm_deltas?]),
      runtime_task_supervisor: config[:runtime_task_supervisor],
      effect_policy: config[:effect_policy]
    }

    ReActRuntimeConfig.new(runtime_opts)
  end

  defp set_run_tool_context(agent, context) when is_map(context) do
    state = StratState.get(agent, %{})
    put_strategy_state(agent, Map.put(state, :run_tool_context, context))
  end

  defp set_run_req_http_options(agent, req_http_options) when is_list(req_http_options) do
    state = StratState.get(agent, %{})
    put_strategy_state(agent, Map.put(state, :run_req_http_options, req_http_options))
  end

  defp set_run_llm_opts(agent, llm_opts) when is_list(llm_opts) do
    state = StratState.get(agent, %{})
    put_strategy_state(agent, Map.put(state, :run_llm_opts, llm_opts))
  end

  defp normalize_action({inner, _meta}), do: normalize_action(inner)
  defp normalize_action(action), do: action

  defp ensure_worker_start(state, worker_start_payload) do
    if is_pid(state[:react_worker_pid]) and Process.alive?(state[:react_worker_pid]) do
      directive =
        AgentDirective.emit_to_pid(
          worker_start_signal(worker_start_payload),
          state[:react_worker_pid]
        )

      new_state =
        state
        |> Map.put(:pending_worker_start, nil)
        |> Map.put(:react_worker_status, :running)

      {new_state, [directive]}
    else
      spawn_directive =
        AgentDirective.spawn_agent(Jido.AI.Reasoning.ReAct.Worker.Agent, @worker_tag)

      new_state =
        state
        |> Map.put(:react_worker_pid, nil)
        |> Map.put(:react_worker_status, :starting)
        |> Map.put(:pending_worker_start, worker_start_payload)

      {new_state, [spawn_directive]}
    end
  end

  defp worker_start_signal(payload) do
    Jido.Signal.new!("ai.react.worker.start", payload, source: @source)
  end

  defp worker_cancel_signal(request_id, reason) do
    Jido.Signal.new!("ai.react.worker.cancel", %{request_id: request_id, reason: reason}, source: @source)
  end

  defp react_worker_tag?(tag), do: tag == @worker_tag or tag == Atom.to_string(@worker_tag)

  defp worker_pid_matches?(expected, actual) when is_pid(expected) and is_pid(actual),
    do: expected == actual

  defp worker_pid_matches?(_expected, _actual), do: true

  defp busy?(state, config) do
    config[:request_policy] == :reject and state[:status] in [:awaiting_llm, :awaiting_tool] and
      is_binary(state[:active_request_id])
  end

  defp maybe_mark_worker_ready(state, kind)
       when kind in [:request_completed, :request_failed, :request_cancelled] do
    Map.put(state, :react_worker_status, :ready)
  end

  defp maybe_mark_worker_ready(state, _kind), do: state

  defp maybe_apply_runtime_effects(agent, event, state) do
    case event_kind(event) do
      :tool_completed ->
        data = event_field(event, :data, %{})
        result = normalize_tool_result(event_field(data, :result, {:error, :unknown, []}))
        policy = effect_policy_from_state(state)

        {agent, directives, _stats, _filtered_result} =
          Effects.apply_result(agent, result, policy)

        {agent, directives}

      _ ->
        {agent, []}
    end
  end

  defp runtime_state_from_context(%AIContext{} = context, query, request_id, run_id)
       when is_binary(query) and is_binary(request_id) and is_binary(run_id) do
    ReActState.new(query, context.system_prompt, request_id: request_id, run_id: run_id)
    |> Map.put(:context, context)
  end

  defp strategy_context(state, config) do
    case Map.get(state, :context) do
      %AIContext{} = context ->
        context

      _ ->
        AIContext.new(system_prompt: config[:system_prompt])
    end
  end

  defp fresh_projection_context(config) when is_map(config) do
    AIContext.new(system_prompt: config[:system_prompt])
  end

  defp fresh_projection_context(_), do: AIContext.new()

  defp snapshot_context(state, config) do
    case Map.get(state, :run_context) do
      %AIContext{} = context -> context
      _ -> strategy_context(state, config)
    end
  end

  defp append_assistant_to_run_context(
         state,
         turn_type,
         text,
         tool_calls,
         thinking_content,
         reasoning_details,
         refs
       ) do
    context = Map.get(state, :run_context) || Map.get(state, :context)

    case context do
      %AIContext{} = context ->
        assistant_tool_calls = if turn_type == :tool_calls, do: tool_calls, else: nil

        assistant_opts =
          []
          |> maybe_put_assistant_context_opt(:thinking, thinking_content)
          |> maybe_put_assistant_context_opt(:reasoning_details, reasoning_details)
          |> maybe_put_assistant_context_opt(:refs, normalize_refs(refs))

        Map.put(
          state,
          :run_context,
          AIContext.append_assistant(context, text, assistant_tool_calls, assistant_opts)
        )

      _ ->
        state
    end
  end

  defp append_tool_result_to_run_context(state, tool_call_id, tool_name, tool_result, refs) do
    context = Map.get(state, :run_context) || Map.get(state, :context)

    case context do
      %AIContext{} = context when is_binary(tool_call_id) and is_binary(tool_name) ->
        content = Turn.format_tool_result_content(tool_result)

        Map.put(
          state,
          :run_context,
          AIContext.append_tool_result(context, tool_call_id, tool_name, content, refs: normalize_refs(refs))
        )

      _ ->
        state
    end
  end

  defp maybe_put_assistant_context_opt(opts, _key, nil), do: opts
  defp maybe_put_assistant_context_opt(opts, _key, ""), do: opts
  defp maybe_put_assistant_context_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp runtime_event_refs(event, fallback_request_id) do
    %{}
    |> maybe_put_ref(:request_id, event_field(event, :request_id, fallback_request_id))
    |> maybe_put_ref(:run_id, event_field(event, :run_id, fallback_request_id))
    |> maybe_put_ref(:signal_id, event_field(event, :id))
    |> normalize_refs()
  end

  defp commit_run_context(state) do
    case Map.get(state, :run_context) do
      %AIContext{} = context -> state |> Map.put(:context, context) |> Map.put(:run_context, nil)
      _ -> state
    end
  end

  defp ensure_request_trace(state, request_id) when is_binary(request_id) do
    traces = Map.get(state, :request_traces, %{})
    trace = Map.get(traces, request_id, %{events: [], truncated?: false})
    Map.put(state, :request_traces, Map.put(traces, request_id, trace))
  end

  defp ensure_request_trace(state, _request_id), do: state

  defp append_trace_event(state, request_id, event) when is_binary(request_id) do
    traces = Map.get(state, :request_traces, %{})
    trace = Map.get(traces, request_id, %{events: [], truncated?: false})

    updated_trace =
      cond do
        trace.truncated? ->
          trace

        length(trace.events) < @request_trace_cap ->
          %{trace | events: trace.events ++ [event]}

        true ->
          %{trace | truncated?: true}
      end

    Map.put(state, :request_traces, Map.put(traces, request_id, updated_trace))
  end

  defp append_trace_event(state, _request_id, _event), do: state

  defp build_config(agent, ctx) do
    opts = ctx[:strategy_opts] || []
    observability_overrides = opts |> Keyword.get(:observability, %{}) |> normalize_map_opt()
    tool_context_opt = opts |> Keyword.get(:tool_context, %{}) |> normalize_map_opt()

    agent_effect_policy =
      Keyword.get(opts, :agent_effect_policy, Keyword.get(opts, :effect_policy, %{}))

    strategy_effect_policy = Keyword.get(opts, :strategy_effect_policy, %{})

    tools_modules =
      case Keyword.fetch(opts, :tools) do
        {:ok, mods} when is_list(mods) ->
          mods

        :error ->
          raise ArgumentError,
                "Jido.AI.Reasoning.ReAct.Strategy requires :tools option (list of Jido.Action modules)"
      end

    actions_by_name = Map.new(tools_modules, &{&1.name(), &1})
    reqllm_tools = ToolAdapter.from_actions(tools_modules)

    raw_model = Keyword.get(opts, :model, Map.get(agent.state, :model, @default_model))
    resolved_model = resolve_model_spec(raw_model)
    provider_opt_keys_by_string = provider_opt_keys_by_string(resolved_model)

    request_policy = validate_request_policy!(Keyword.get(opts, :request_policy, :reject))
    effect_policy = Effects.intersect_policies(agent_effect_policy, strategy_effect_policy)

    %{
      tools: tools_modules,
      reqllm_tools: reqllm_tools,
      actions_by_name: actions_by_name,
      request_transformer: validate_request_transformer_opt!(Keyword.get(opts, :request_transformer)),
      system_prompt: normalize_system_prompt_opt(opts),
      model: resolved_model,
      max_iterations: Keyword.get(opts, :max_iterations, @default_max_iterations),
      max_tokens: Keyword.get(opts, :max_tokens, @default_max_tokens),
      streaming: Keyword.get(opts, :streaming, true),
      stream_receive_timeout_ms:
        opts
        |> Keyword.get(:stream_receive_timeout_ms, Keyword.get(opts, :stream_timeout_ms, 30_000))
        |> normalize_stream_receive_timeout_ms(30_000),
      request_policy: request_policy,
      stream_timeout_ms: Keyword.get(opts, :stream_timeout_ms, 0),
      tool_timeout_ms: Keyword.get(opts, :tool_timeout_ms, 15_000),
      tool_max_retries: Keyword.get(opts, :tool_max_retries, 1),
      tool_retry_backoff_ms: Keyword.get(opts, :tool_retry_backoff_ms, 200),
      effect_policy: effect_policy,
      runtime_adapter: true,
      runtime_task_supervisor: Keyword.get(opts, :runtime_task_supervisor),
      observability:
        Map.merge(
          %{
            emit_telemetry?: true,
            emit_lifecycle_signals?: true,
            redact_tool_args?: true,
            emit_llm_deltas?: true
          },
          observability_overrides
        ),
      agent_id: agent.id,
      base_tool_context: Map.get(agent.state, :tool_context) || tool_context_opt,
      base_req_http_options: opts |> Keyword.get(:req_http_options, []) |> normalize_req_http_options(),
      base_llm_opts: opts |> Keyword.get(:llm_opts, []) |> normalize_llm_opts(provider_opt_keys_by_string),
      provider_opt_keys_by_string: provider_opt_keys_by_string
    }
  end

  defp normalize_system_prompt_opt(opts) do
    case Keyword.fetch(opts, :system_prompt) do
      :error ->
        @default_system_prompt

      {:ok, prompt} when is_binary(prompt) and prompt != "" ->
        prompt

      {:ok, prompt} when prompt in [nil, false, ""] ->
        nil

      {:ok, other} ->
        raise ArgumentError,
              "invalid system_prompt: expected binary, nil, or false, got #{inspect(other)}"
    end
  end

  defp resolve_model_spec(model), do: Jido.AI.ModelInput.normalize!(model)

  defp validate_request_policy!(:reject), do: :reject

  defp validate_request_policy!(other) do
    raise ArgumentError,
          "unsupported request_policy #{inspect(other)} for ReAct; supported values: [:reject]"
  end

  defp normalize_map_opt(%{} = value), do: value
  defp normalize_map_opt({:%{}, _meta, pairs}) when is_list(pairs), do: Map.new(pairs)
  defp normalize_map_opt(_), do: %{}

  defp resolve_request_tools(config, params) do
    base_tools = config[:actions_by_name] || %{}
    override_tools = Map.get(params, :tools)
    allowed_tools = Map.get(params, :allowed_tools)

    case ToolSelection.resolve(base_tools, override_tools, allowed_tools) do
      {:ok, tools} ->
        {:ok, tools}

      {:error, :invalid_tools} ->
        {:error, :invalid_tools, "Invalid tools override for this request"}

      {:error, :invalid_allowed_tools} ->
        {:error, :invalid_allowed_tools, "allowed_tools must be a list of tool names"}

      {:error, {:unknown_allowed_tools, unknown}} ->
        {:error, :unknown_allowed_tools, "Unknown allowed_tools: #{Enum.join(unknown, ", ")}"}

      {:error, {:invalid_action, module, reason}} ->
        {:error, :invalid_tools, "Invalid tool #{inspect(module)}: #{inspect(reason)}"}
    end
  end

  defp resolve_request_transformer(config, params) do
    case validate_request_transformer(Map.get(params, :request_transformer, config[:request_transformer])) do
      {:ok, module} ->
        {:ok, module}

      {:error, message} ->
        {:error, :invalid_request_transformer, message}
    end
  end

  defp validate_request_transformer_opt!(request_transformer) do
    case validate_request_transformer(request_transformer) do
      {:ok, module} ->
        module

      {:error, message} ->
        raise ArgumentError, message
    end
  end

  defp validate_request_transformer(nil), do: {:ok, nil}

  defp validate_request_transformer(request_transformer) do
    case RequestTransformer.validate(request_transformer) do
      {:ok, module} ->
        {:ok, module}

      {:error, {:request_transformer_not_loaded, module}} ->
        {:error, "Request transformer #{inspect(module)} is not loaded"}

      {:error, {:request_transformer_missing_callback, module}} ->
        {:error, "Request transformer #{inspect(module)} must implement transform_request/4"}

      {:error, :invalid_request_transformer} ->
        {:error, "request_transformer must be a module implementing transform_request/4"}
    end
  end

  defp resolve_stream_timeout_ms_opt(opts, default) when is_list(opts) do
    case Keyword.fetch(opts, :stream_timeout_ms) do
      {:ok, value} when is_integer(value) and value >= 0 ->
        value

      _ ->
        case Keyword.fetch(opts, :stream_receive_timeout_ms) do
          {:ok, value} when is_integer(value) and value > 0 ->
            value

          _ ->
            default
        end
    end
  end

  defp normalize_stream_receive_timeout_ms(value, _default)
       when is_integer(value) and value > 0 do
    value
  end

  defp normalize_stream_receive_timeout_ms(_value, default), do: default

  defp effect_policy_from_state(state) do
    state
    |> normalize_map_opt()
    |> Map.get(:config, %{})
    |> normalize_map_opt()
    |> Map.get(:effect_policy, Effects.default_policy())
  end

  defp normalize_tool_result(result), do: Effects.normalize_result(result)

  defp normalize_req_http_options(req_http_options) when is_list(req_http_options),
    do: req_http_options

  defp normalize_req_http_options(_), do: []

  defp normalize_llm_opts(llm_opts, provider_opt_keys_by_string) when is_list(llm_opts) do
    normalize_llm_opt_pairs(llm_opts, provider_opt_keys_by_string)
  end

  defp normalize_llm_opts(llm_opts, provider_opt_keys_by_string) when is_map(llm_opts) do
    llm_opts
    |> Enum.map(fn {key, value} ->
      normalized_key = normalize_llm_opt_key(key)

      normalized_value =
        normalize_llm_opt_value(normalized_key, value, provider_opt_keys_by_string)

      {normalized_key, normalized_value}
    end)
    |> normalize_llm_opt_pairs(provider_opt_keys_by_string)
  end

  defp normalize_llm_opts(_llm_opts, _provider_opt_keys_by_string), do: []

  defp normalize_llm_opt_pairs(pairs, provider_opt_keys_by_string) when is_list(pairs) do
    pairs
    |> Enum.reduce([], fn
      {key, value}, acc when is_atom(key) and not is_nil(key) ->
        normalized_value = normalize_llm_opt_value(key, value, provider_opt_keys_by_string)
        [{key, normalized_value} | acc]

      _other, acc ->
        acc
    end)
    |> Enum.reverse()
  end

  defp normalize_llm_opt_key(key) when is_atom(key), do: key

  defp normalize_llm_opt_key(key) when is_binary(key) do
    Map.get(@reqllm_generation_opt_keys_by_string, key) || maybe_to_existing_atom(key)
  end

  defp normalize_llm_opt_key(_), do: nil

  defp normalize_llm_opt_value(:provider_options, value, provider_opt_keys_by_string) do
    normalize_provider_options(value, provider_opt_keys_by_string)
  end

  defp normalize_llm_opt_value(_key, value, _provider_opt_keys_by_string), do: value

  defp normalize_provider_options(value, provider_opt_keys_by_string) when is_list(value) do
    normalize_provider_option_pairs(value, provider_opt_keys_by_string)
  end

  defp normalize_provider_options(value, provider_opt_keys_by_string) when is_map(value) do
    value
    |> Enum.map(fn {key, entry_value} ->
      {normalize_provider_opt_key(key, provider_opt_keys_by_string), entry_value}
    end)
    |> normalize_provider_option_pairs(provider_opt_keys_by_string)
  end

  defp normalize_provider_options(value, _provider_opt_keys_by_string), do: value

  defp normalize_provider_option_pairs(pairs, _provider_opt_keys_by_string) do
    pairs
    |> Enum.reduce([], fn
      {key, value}, acc when is_atom(key) and not is_nil(key) ->
        [{key, value} | acc]

      _other, acc ->
        acc
    end)
    |> Enum.reverse()
  end

  defp normalize_provider_opt_key(key, _provider_opt_keys_by_string) when is_atom(key), do: key

  defp normalize_provider_opt_key(key, provider_opt_keys_by_string) when is_binary(key) do
    Map.get(provider_opt_keys_by_string, key) || maybe_to_existing_atom(key)
  end

  defp normalize_provider_opt_key(_key, _provider_opt_keys_by_string), do: nil

  defp maybe_to_existing_atom(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> nil
    end
  end

  defp provider_opt_keys_by_string(model_spec),
    do: Jido.AI.ModelInput.provider_opt_keys(model_spec)

  defp generate_call_id, do: "req_#{Jido.Util.generate_id()}"

  defp put_strategy_state(%Agent{} = agent, state) when is_map(state) do
    %{agent | state: Map.put(agent.state, StratState.key(), state)}
  end

  @doc """
  Returns the list of currently registered tools for the given agent.
  """
  @spec list_tools(Agent.t()) :: [module()]
  def list_tools(%Agent{} = agent) do
    state = StratState.get(agent, %{})
    config = state[:config] || %{}
    config[:tools] || []
  end
end
