defmodule Jido.AI.Strategies.ReAct do
  @moduledoc """
  Generic ReAct (Reason-Act) execution strategy for Jido agents.

  This strategy implements a multi-step reasoning loop:
  1. User query arrives -> Start LLM call with tools
  2. LLM response -> Either tool calls or final answer
  3. Tool results -> Continue with next LLM call
  4. Repeat until final answer or max iterations

  ## Architecture

  This strategy uses a pure state machine (`Jido.AI.ReAct.Machine`) for all state
  transitions. The strategy acts as a thin adapter that:
  - Converts instructions to machine messages
  - Converts machine directives to SDK-specific directive structs
  - Manages the machine state within the agent

  ## Configuration

  Configure via strategy options when defining your agent:

      use Jido.Agent,
        name: "my_react_agent",
        strategy: {
          Jido.AI.Strategies.ReAct,
          tools: [MyApp.Actions.Calculator, MyApp.Actions.Search],
          system_prompt: "You are a helpful assistant...",
          model: "anthropic:claude-haiku-4-5",
          max_iterations: 10
        }

  ### Options

  - `:tools` (required) - List of Jido.Action modules to use as tools
  - `:system_prompt` (optional) - Custom system prompt for the LLM
  - `:model` (optional) - Model identifier, defaults to agent's `:model` state or "anthropic:claude-haiku-4-5"
  - `:max_iterations` (optional) - Maximum reasoning iterations, defaults to 10

  ## Signal Routing

  This strategy implements `signal_routes/1` which AgentServer uses to
  automatically route these signals to strategy commands:

  - `"ai.react.query"` -> `:ai_react_start`
  - `"ai.llm.response"` -> `:ai_react_llm_result`
  - `"ai.tool.result"` -> `:ai_react_tool_result`
  - `"ai.llm.delta"` -> `:ai_react_llm_partial`

  No custom signal handling code is needed in your agent.

  ## State

  State is stored under `agent.state.__strategy__` with the following shape:

      %{
        status: :idle | :awaiting_llm | :awaiting_tool | :completed | :error,
        iteration: non_neg_integer(),
        conversation: [ReqLLM.Message.t()],
        pending_tool_calls: [%{id: String.t(), name: String.t(), arguments: map(), result: term()}],
        final_answer: String.t() | nil,
        current_llm_call_id: String.t() | nil,
        termination_reason: :final_answer | :max_iterations | :error | nil,
        config: config(),
        run_tool_context: map() | nil  # Ephemeral per-request context
      }

  ## Tool Context

  Tool context is separated into two scopes to prevent cross-request data leakage:

  - **`base_tool_context`** (persistent, in `config`) - Set at agent definition time via
    `:tool_context` option. Represents stable context like domain modules. Updated only
    via explicit `ai.react.set_tool_context` action (replaces, not merges).

  - **`run_tool_context`** (ephemeral, in state) - Set per-request via `tool_context:`
    option in `ai.react.start`. Automatically cleared when the machine reaches `:completed`
    or `:error` status. Never persists across requests.

  At tool execution time, both contexts are merged (run overrides base) to produce the
  effective context passed to actions. This ensures multi-tenant isolation - a tenant's
  request context cannot leak to subsequent requests.
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Directive
  alias Jido.AI.ReAct.Machine
  alias Jido.AI.Strategy.StateOpsHelpers
  alias Jido.AI.ToolAdapter
  alias ReqLLM.Context

  @type config :: %{
          tools: [module()],
          reqllm_tools: [ReqLLM.Tool.t()],
          actions_by_name: %{String.t() => module()},
          system_prompt: String.t(),
          model: String.t(),
          max_iterations: pos_integer(),
          base_tool_context: map(),
          request_policy: :reject,
          tool_timeout_ms: pos_integer(),
          tool_max_retries: non_neg_integer(),
          tool_retry_backoff_ms: non_neg_integer(),
          observability: map(),
          agent_id: String.t() | nil
        }

  @default_model "anthropic:claude-haiku-4-5"
  @default_max_iterations 10
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

  @doc "Returns the action atom for starting a ReAct conversation."
  @spec start_action() :: :ai_react_start
  def start_action, do: @start

  @doc "Returns the action atom for handling LLM results."
  @spec llm_result_action() :: :ai_react_llm_result
  def llm_result_action, do: @llm_result

  @doc "Returns the action atom for registering a tool dynamically."
  @spec register_tool_action() :: :ai_react_register_tool
  def register_tool_action, do: @register_tool

  @doc "Returns the action atom for unregistering a tool."
  @spec unregister_tool_action() :: :ai_react_unregister_tool
  def unregister_tool_action, do: @unregister_tool

  @doc "Returns the action atom for handling tool results."
  @spec tool_result_action() :: :ai_react_tool_result
  def tool_result_action, do: @tool_result

  @doc "Returns the action atom for handling streaming LLM partial tokens."
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

  @action_specs %{
    @start => %{
      schema:
        Zoi.object(%{
          query: Zoi.string(),
          request_id: Zoi.string() |> Zoi.optional(),
          tool_context: Zoi.map() |> Zoi.optional()
        }),
      doc: "Start a new ReAct conversation with a user query",
      name: "ai.react.start"
    },
    @llm_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), result: Zoi.any()}),
      doc: "Handle LLM response (tool calls or final answer)",
      name: "ai.react.llm_result"
    },
    @tool_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), tool_name: Zoi.string(), result: Zoi.any()}),
      doc: "Handle tool execution result",
      name: "ai.react.tool_result"
    },
    @llm_partial => %{
      schema:
        Zoi.object(%{
          call_id: Zoi.string(),
          delta: Zoi.string(),
          chunk_type: Zoi.atom() |> Zoi.default(:content)
        }),
      doc: "Handle streaming LLM token chunk",
      name: "ai.react.llm_partial"
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
      doc: "Update the tool context for subsequent tool executions",
      name: "ai.react.set_tool_context"
    }
  }

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"ai.react.query", {:strategy_cmd, @start}},
      {"ai.llm.response", {:strategy_cmd, @llm_result}},
      {"ai.tool.result", {:strategy_cmd, @tool_result}},
      {"ai.llm.delta", {:strategy_cmd, @llm_partial}},
      {"ai.react.cancel", {:strategy_cmd, @cancel}},
      {"ai.request.error", {:strategy_cmd, @request_error}},
      {"ai.react.register_tool", {:strategy_cmd, @register_tool}},
      {"ai.react.unregister_tool", {:strategy_cmd, @unregister_tool}},
      {"ai.react.set_tool_context", {:strategy_cmd, @set_tool_context}},
      {"ai.request.started", Jido.Actions.Control.Noop},
      {"ai.request.completed", Jido.Actions.Control.Noop},
      {"ai.request.failed", Jido.Actions.Control.Noop},
      # Usage report is emitted for observability but doesn't need processing
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
      conversation: Map.get(state, :conversation, []),
      current_llm_call_id: state[:current_llm_call_id],
      active_request_id: state[:active_request_id],
      cancel_reason: state[:cancel_reason],
      model: config[:model],
      max_iterations: config[:max_iterations],
      request_policy: config[:request_policy],
      tool_timeout_ms: config[:tool_timeout_ms],
      tool_max_retries: config[:tool_max_retries],
      tool_retry_backoff_ms: config[:tool_retry_backoff_ms],
      available_tools: Enum.map(Map.get(config, :tools, []), & &1.name())
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
    machine = Machine.new()

    state =
      machine
      |> Machine.to_map()
      |> Map.put(:agent_id, Map.get(agent, :id))
      |> StateOpsHelpers.apply_to_state([StateOpsHelpers.update_config(config)])

    agent = StratState.put(agent, state)
    {agent, []}
  end

  @impl true
  def cmd(%Agent{} = agent, instructions, _ctx) do
    {agent, dirs_rev} =
      Enum.reduce(instructions, {agent, []}, fn instr, {acc_agent, acc_dirs} ->
        case process_instruction(acc_agent, instr) do
          {new_agent, new_dirs} ->
            {new_agent, Enum.reverse(new_dirs, acc_dirs)}

          :noop ->
            {acc_agent, acc_dirs}
        end
      end)

    {agent, Enum.reverse(dirs_rev)}
  end

  defp process_instruction(agent, %Jido.Instruction{action: action, params: params}) do
    normalized_action = normalize_action(action)

    # Handle tool registration/unregistration/context separately (not machine messages)
    case normalized_action do
      @register_tool ->
        process_register_tool(agent, params)

      @unregister_tool ->
        process_unregister_tool(agent, params)

      @set_tool_context ->
        process_set_tool_context(agent, params)

      @request_error ->
        process_request_error(agent, params)

      @start ->
        # Store per-request tool_context in run_tool_context (ephemeral, cleared on completion)
        # This does NOT mutate base_tool_context - prevents cross-request leakage
        run_context = Map.get(params, :tool_context) || %{}
        agent = set_run_tool_context(agent, run_context)

        process_machine_message(agent, normalized_action, params)

      _ ->
        process_machine_message(agent, normalized_action, params)
    end
  end

  defp process_machine_message(agent, action, params) do
    case to_machine_msg(action, params) do
      msg when not is_nil(msg) ->
        state = StratState.get(agent, %{})
        config = state[:config]
        machine = Machine.from_map(state)

        env = %{
          system_prompt: config[:system_prompt],
          max_iterations: config[:max_iterations],
          request_policy: config[:request_policy],
          observability: config[:observability] || %{},
          telemetry_metadata: %{
            agent_id: state[:agent_id] || Map.get(agent, :id),
            thread_id: thread_id_from_state(state)
          }
        }

        {machine, directives} = Machine.update(machine, msg, env)

        machine_state = Machine.to_map(machine)

        # Preserve run_tool_context through the state update
        new_state =
          machine_state
          |> Map.put(:run_tool_context, state[:run_tool_context])
          |> Map.put(:agent_id, state[:agent_id] || Map.get(agent, :id))
          |> StateOpsHelpers.apply_to_state([StateOpsHelpers.update_config(config)])

        # Clear run_tool_context on terminal states to prevent cross-request leakage
        new_state =
          if machine_state[:status] in [:completed, :error] do
            Map.delete(new_state, :run_tool_context)
          else
            new_state
          end

        agent = StratState.put(agent, new_state)
        {agent, lift_directives(directives, config, new_state)}

      _ ->
        :noop
    end
  end

  defp process_register_tool(agent, %{tool_module: module}) when is_atom(module) do
    state = StratState.get(agent, %{})
    config = state[:config]

    # Add the tool to the config
    new_tools = [module | config[:tools]] |> Enum.uniq()
    new_actions_by_name = Map.put(config[:actions_by_name], module.name(), module)
    new_reqllm_tools = ToolAdapter.from_actions(new_tools)

    new_state =
      StateOpsHelpers.apply_to_state(
        state,
        StateOpsHelpers.update_tools_config(new_tools, new_actions_by_name, new_reqllm_tools)
      )

    agent = StratState.put(agent, new_state)
    {agent, []}
  end

  defp process_unregister_tool(agent, %{tool_name: tool_name}) when is_binary(tool_name) do
    state = StratState.get(agent, %{})
    config = state[:config]

    # Remove the tool from the config
    new_tools = Enum.reject(config[:tools], fn m -> m.name() == tool_name end)
    new_actions_by_name = Map.delete(config[:actions_by_name], tool_name)
    new_reqllm_tools = ToolAdapter.from_actions(new_tools)

    new_state =
      StateOpsHelpers.apply_to_state(
        state,
        StateOpsHelpers.update_tools_config(new_tools, new_actions_by_name, new_reqllm_tools)
      )

    agent = StratState.put(agent, new_state)
    {agent, []}
  end

  defp process_set_tool_context(agent, %{tool_context: new_context}) when is_map(new_context) do
    state = StratState.get(agent, %{})

    # REPLACE base_tool_context (not merge) to avoid indefinite key accumulation
    # Use set_config_field to replace just this field without deep merging
    new_state =
      StateOpsHelpers.apply_to_state(state, [
        StateOpsHelpers.set_config_field(:base_tool_context, new_context)
      ])

    agent = StratState.put(agent, new_state)
    {agent, []}
  end

  defp process_request_error(agent, %{request_id: request_id, reason: reason, message: message}) do
    state = StratState.get(agent, %{})
    new_state = Map.put(state, :last_request_error, %{request_id: request_id, reason: reason, message: message})
    agent = StratState.put(agent, new_state)
    {agent, []}
  end

  # Sets ephemeral per-request tool context (cleared on completion)
  defp set_run_tool_context(agent, context) when is_map(context) do
    state = StratState.get(agent, %{})
    new_state = Map.put(state, :run_tool_context, context)
    StratState.put(agent, new_state)
  end

  defp normalize_action({inner, _meta}), do: normalize_action(inner)
  defp normalize_action(action), do: action

  defp to_machine_msg(@start, %{query: query} = params) do
    request_id =
      case Map.get(params, :request_id) do
        id when is_binary(id) -> id
        _ -> generate_call_id()
      end

    {:start, query, request_id}
  end

  defp to_machine_msg(@llm_result, %{call_id: call_id, result: result}) do
    {:llm_result, call_id, result}
  end

  defp to_machine_msg(@tool_result, %{call_id: call_id, result: result}) do
    {:tool_result, call_id, result}
  end

  defp to_machine_msg(@llm_partial, %{call_id: call_id, delta: delta, chunk_type: chunk_type}) do
    {:llm_partial, call_id, delta, chunk_type}
  end

  defp to_machine_msg(@cancel, params) do
    {:cancel, Map.get(params, :request_id), Map.get(params, :reason, :user_cancelled)}
  end

  defp to_machine_msg(_, _), do: nil

  defp lift_directives(directives, config, state) do
    %{
      model: model,
      reqllm_tools: reqllm_tools,
      actions_by_name: actions_by_name,
      base_tool_context: base_tool_context,
      tool_timeout_ms: tool_timeout_ms,
      tool_max_retries: tool_max_retries,
      tool_retry_backoff_ms: tool_retry_backoff_ms,
      observability: observability,
      agent_id: agent_id
    } = config

    # Merge base (persistent) + run (ephemeral) context at directive emission time
    # Run context overrides base context; neither is mutated
    run_tool_context = Map.get(state, :run_tool_context, %{})
    effective_tool_context = Map.merge(base_tool_context || %{}, run_tool_context)
    agent_id = Map.get(state, :agent_id) || agent_id
    thread_id = thread_id_from_state(state)

    Enum.flat_map(directives, fn
      {:call_llm_stream, id, conversation} ->
        [
          Directive.LLMStream.new!(%{
            id: id,
            model: model,
            context: convert_to_reqllm_context(conversation),
            tools: reqllm_tools,
            metadata: %{
              request_id: state[:active_request_id],
              run_id: state[:active_request_id],
              iteration: state[:iteration],
              agent_id: agent_id,
              thread_id: thread_id,
              observability: observability
            }
          })
        ]

      {:exec_tool, id, tool_name, arguments} ->
        case lookup_tool(tool_name, actions_by_name, config) do
          {:ok, action_module} ->
            # Include call_id and iteration for telemetry correlation
            exec_context =
              effective_tool_context
              |> Map.merge(%{
                call_id: id,
                iteration: state[:iteration],
                request_id: state[:active_request_id],
                run_id: state[:active_request_id],
                agent_id: agent_id,
                thread_id: thread_id,
                observability: observability
              })
              |> Enum.reject(fn {_key, value} -> is_nil(value) end)
              |> Map.new()

            [
              Directive.ToolExec.new!(%{
                id: id,
                tool_name: tool_name,
                action_module: action_module,
                arguments: arguments,
                context: exec_context,
                timeout_ms: tool_timeout_ms,
                max_retries: tool_max_retries,
                retry_backoff_ms: tool_retry_backoff_ms,
                request_id: state[:active_request_id],
                iteration: state[:iteration],
                metadata: %{
                  request_id: state[:active_request_id],
                  run_id: state[:active_request_id],
                  iteration: state[:iteration],
                  agent_id: agent_id,
                  thread_id: thread_id,
                  observability: observability
                }
              })
            ]

          :error ->
            # Issue #1 fix: Never silently drop - emit error result for unknown tools
            # This ensures the Machine receives a tool_result and doesn't deadlock
            [
              Directive.EmitToolError.new!(%{
                id: id,
                tool_name: tool_name,
                error: {:unknown_tool, "Tool '#{tool_name}' not found in registered actions"}
              })
            ]
        end

      # Issue #3 fix: Handle request rejection when agent is busy
      {:request_error, request_id, reason, message} ->
        [
          Directive.EmitRequestError.new!(%{
            request_id: request_id,
            reason: reason,
            message: message
          })
        ]
    end)
  end

  # Looks up a tool by name in actions_by_name
  defp lookup_tool(tool_name, actions_by_name, _config) do
    Map.fetch(actions_by_name, tool_name)
  end

  defp convert_to_reqllm_context(conversation) do
    {:ok, context} = Context.normalize(conversation, validate: false)
    Context.to_list(context)
  end

  defp thread_id_from_state(state) when is_map(state) do
    case Map.get(state, :thread) do
      %{id: id} when is_binary(id) -> id
      _ -> nil
    end
  end

  defp build_config(agent, ctx) do
    opts = ctx[:strategy_opts] || []
    observability_overrides = opts |> Keyword.get(:observability, %{}) |> normalize_map_opt()
    tool_context_opt = opts |> Keyword.get(:tool_context, %{}) |> normalize_map_opt()

    tools_modules =
      case Keyword.fetch(opts, :tools) do
        {:ok, mods} when is_list(mods) ->
          mods

        :error ->
          raise ArgumentError,
                "Jido.AI.Strategies.ReAct requires :tools option (list of Jido.Action modules)"
      end

    actions_by_name = Map.new(tools_modules, &{&1.name(), &1})
    reqllm_tools = ToolAdapter.from_actions(tools_modules)

    # Resolve model - can be an alias atom (:fast, :capable) or a full spec string
    raw_model = Keyword.get(opts, :model, Map.get(agent.state, :model, @default_model))
    resolved_model = resolve_model_spec(raw_model)

    request_policy =
      case Keyword.get(opts, :request_policy, :reject) do
        :reject -> :reject
        _ -> :reject
      end

    %{
      tools: tools_modules,
      reqllm_tools: reqllm_tools,
      actions_by_name: actions_by_name,
      system_prompt: Keyword.get(opts, :system_prompt, @default_system_prompt),
      model: resolved_model,
      max_iterations: Keyword.get(opts, :max_iterations, @default_max_iterations),
      request_policy: request_policy,
      tool_timeout_ms: Keyword.get(opts, :tool_timeout_ms, 15_000),
      tool_max_retries: Keyword.get(opts, :tool_max_retries, 1),
      tool_retry_backoff_ms: Keyword.get(opts, :tool_retry_backoff_ms, 200),
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
      # base_tool_context is the persistent context from agent definition
      # per-request context is stored separately in state[:run_tool_context]
      base_tool_context: Map.get(agent.state, :tool_context) || tool_context_opt
    }
  end

  # Resolves model aliases to full specs, passes through strings unchanged
  defp resolve_model_spec(model) when is_atom(model) do
    Jido.AI.resolve_model(model)
  end

  defp resolve_model_spec(model) when is_binary(model) do
    model
  end

  defp normalize_map_opt(%{} = value), do: value
  defp normalize_map_opt({:%{}, _meta, pairs}) when is_list(pairs), do: Map.new(pairs)
  defp normalize_map_opt(_), do: %{}

  defp generate_call_id, do: Machine.generate_call_id()

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
