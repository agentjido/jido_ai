defmodule Jido.AI.Strategies.RLM do
  @moduledoc """
  RLM (Recursive Language Model) execution strategy for Jido agents.

  Implements iterative context exploration with sub-LLM delegation using native
  BEAM/Jido semantics. Uses the ReAct state machine internally for the
  awaiting_llm ↔ awaiting_tool cycle, adding RLM-specific tools, prompts,
  and context/workspace management.

  ## Configuration

      use Jido.Agent,
        name: "my_rlm_agent",
        strategy: {
          Jido.AI.Strategies.RLM,
          model: "anthropic:claude-sonnet-4-20250514",
          recursive_model: "anthropic:claude-haiku-4-5",
          max_iterations: 15,
          extra_tools: []
        }
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Directive
  alias Jido.AI.ReAct.Machine
  alias Jido.AI.RLM.{ContextStore, WorkspaceStore, Prompts}
  alias Jido.AI.Strategy.StateOpsHelpers
  alias Jido.AI.ToolAdapter
  alias ReqLLM.Context

  @rlm_tools [
    Jido.AI.Actions.RLM.Context.Stats,
    Jido.AI.Actions.RLM.Context.Chunk,
    Jido.AI.Actions.RLM.Context.ReadChunk,
    Jido.AI.Actions.RLM.Context.Search,
    Jido.AI.Actions.RLM.Workspace.Note,
    Jido.AI.Actions.RLM.Workspace.GetSummary,
    Jido.AI.Actions.RLM.LLM.SubqueryBatch
  ]

  @default_model "anthropic:claude-sonnet-4-20250514"
  @default_recursive_model "anthropic:claude-haiku-4-5"
  @default_max_iterations 15
  @default_context_inline_threshold 2_000_000
  @default_max_concurrency 10

  @start :rlm_start
  @llm_result :rlm_llm_result
  @tool_result :rlm_tool_result
  @llm_partial :rlm_llm_partial

  @spec start_action() :: :rlm_start
  def start_action, do: @start

  @spec llm_result_action() :: :rlm_llm_result
  def llm_result_action, do: @llm_result

  @spec tool_result_action() :: :rlm_tool_result
  def tool_result_action, do: @tool_result

  @spec llm_partial_action() :: :rlm_llm_partial
  def llm_partial_action, do: @llm_partial

  @action_specs %{
    @start => %{
      schema:
        Zoi.object(%{
          query: Zoi.string(),
          context: Zoi.any() |> Zoi.optional(),
          context_ref: Zoi.map() |> Zoi.optional(),
          tool_context: Zoi.map() |> Zoi.optional()
        }),
      doc: "Start RLM context exploration with a query and large context",
      name: "rlm.start"
    },
    @llm_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), result: Zoi.any()}),
      doc: "Handle LLM response",
      name: "rlm.llm_result"
    },
    @tool_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), tool_name: Zoi.string(), result: Zoi.any()}),
      doc: "Handle tool execution result",
      name: "rlm.tool_result"
    },
    @llm_partial => %{
      schema:
        Zoi.object(%{
          call_id: Zoi.string(),
          delta: Zoi.string(),
          chunk_type: Zoi.atom() |> Zoi.default(:content)
        }),
      doc: "Handle streaming LLM token",
      name: "rlm.llm_partial"
    }
  }

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"rlm.explore", {:strategy_cmd, @start}},
      {"react.llm.response", {:strategy_cmd, @llm_result}},
      {"react.tool.result", {:strategy_cmd, @tool_result}},
      {"react.llm.delta", {:strategy_cmd, @llm_partial}},
      {"react.usage", Jido.Actions.Control.Noop}
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
      model: config[:model],
      max_iterations: config[:max_iterations],
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

    case normalized_action do
      @start ->
        state = StratState.get(agent, %{})
        config = state[:config]

        context_ref =
          cond do
            is_binary(Map.get(params, :context)) ->
              store_context(params, config)

            is_map(Map.get(params, :context_ref)) ->
              params.context_ref

            true ->
              nil
          end

        request_id = Jido.Util.generate_id()
        {:ok, workspace_ref} = WorkspaceStore.init(request_id)

        run_context =
          (Map.get(params, :tool_context) || %{})
          |> Map.put(:context_ref, context_ref)
          |> Map.put(:workspace_ref, workspace_ref)
          |> Map.put(:recursive_model, config[:recursive_model])
          |> Map.put(:current_depth, get_in(params, [:tool_context, :current_depth]) || 0)
          |> Map.put(:max_depth, config[:max_depth])
          |> Map.put(:child_agent, config[:child_agent])

        agent = set_run_tool_context(agent, run_context)

        agent =
          store_rlm_state(agent, %{
            query: params.query,
            context_ref: context_ref,
            workspace_ref: workspace_ref
          })

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
          max_iterations: config[:max_iterations]
        }

        {machine, directives} = Machine.update(machine, msg, env)

        machine_state = Machine.to_map(machine)

        new_state =
          machine_state
          |> Map.put(:run_tool_context, state[:run_tool_context])
          |> Map.put(:query, state[:query])
          |> Map.put(:context_ref, state[:context_ref])
          |> Map.put(:workspace_ref, state[:workspace_ref])
          |> StateOpsHelpers.apply_to_state([StateOpsHelpers.update_config(config)])

        new_state = maybe_finalize(new_state, machine_state[:status])

        agent = StratState.put(agent, new_state)
        {agent, lift_directives(directives, config, new_state)}

      _ ->
        :noop
    end
  end

  defp lift_directives(directives, config, state) do
    %{
      model: model,
      reqllm_tools: reqllm_tools,
      actions_by_name: actions_by_name,
      base_tool_context: base_tool_context
    } = config

    run_tool_context = Map.get(state, :run_tool_context, %{})
    effective_tool_context = Map.merge(base_tool_context || %{}, run_tool_context)

    Enum.flat_map(directives, fn
      {:call_llm_stream, id, conversation} ->
        workspace_summary = get_workspace_summary(state)
        iteration = state[:iteration] || 1
        current_depth = get_in(state, [:run_tool_context, :current_depth]) || 0
        max_depth_val = get_in(state, [:run_tool_context, :max_depth]) || 0

        next_step =
          Prompts.next_step_prompt(%{
            query: state[:query],
            iteration: iteration,
            workspace_summary: workspace_summary,
            current_depth: current_depth,
            max_depth: max_depth_val
          })

        augmented = conversation ++ [next_step]

        effective_tools = filter_tools_for_depth(reqllm_tools, current_depth, max_depth_val)

        [
          Directive.LLMStream.new!(%{
            id: id,
            model: model,
            context: convert_to_reqllm_context(augmented),
            tools: effective_tools
          })
        ]

      {:exec_tool, id, tool_name, arguments} ->
        case lookup_tool(tool_name, actions_by_name) do
          {:ok, action_module} ->
            exec_context =
              Map.merge(effective_tool_context, %{
                call_id: id,
                iteration: state[:iteration]
              })

            [
              Directive.ToolExec.new!(%{
                id: id,
                tool_name: tool_name,
                action_module: action_module,
                arguments: arguments,
                context: exec_context
              })
            ]

          :error ->
            [
              Directive.EmitToolError.new!(%{
                id: id,
                tool_name: tool_name,
                error: {:unknown_tool, "Tool '#{tool_name}' not found in registered actions"}
              })
            ]
        end

      {:request_error, call_id, reason, message} ->
        [
          Directive.EmitRequestError.new!(%{
            call_id: call_id,
            reason: reason,
            message: message
          })
        ]
    end)
  end

  defp lookup_tool(tool_name, actions_by_name) do
    Map.fetch(actions_by_name, tool_name)
  end

  defp convert_to_reqllm_context(conversation) do
    {:ok, context} = Context.normalize(conversation, validate: false)
    Context.to_list(context)
  end

  defp build_config(agent, ctx) do
    opts = ctx[:strategy_opts] || []

    extra_tools =
      case Keyword.fetch(opts, :extra_tools) do
        {:ok, mods} when is_list(mods) -> mods
        _ -> []
      end

    max_depth = Keyword.get(opts, :max_depth, 0)

    spawn_tools =
      if max_depth > 0 do
        [Jido.AI.Actions.RLM.Agent.Spawn]
      else
        []
      end

    tools_modules = @rlm_tools ++ spawn_tools ++ extra_tools

    actions_by_name = Map.new(tools_modules, &{&1.name(), &1})
    reqllm_tools = ToolAdapter.from_actions(tools_modules)

    raw_model = Keyword.get(opts, :model, Map.get(agent.state, :model, @default_model))
    resolved_model = resolve_model_spec(raw_model)

    raw_recursive = Keyword.get(opts, :recursive_model, @default_recursive_model)
    resolved_recursive = resolve_model_spec(raw_recursive)

    config = %{
      tools: tools_modules,
      reqllm_tools: reqllm_tools,
      actions_by_name: actions_by_name,
      model: resolved_model,
      recursive_model: resolved_recursive,
      max_iterations: Keyword.get(opts, :max_iterations, @default_max_iterations),
      context_inline_threshold: Keyword.get(opts, :context_inline_threshold, @default_context_inline_threshold),
      max_concurrency: Keyword.get(opts, :max_concurrency, @default_max_concurrency),
      base_tool_context: Map.get(agent.state, :tool_context) || Keyword.get(opts, :tool_context, %{}),
      max_depth: max_depth,
      child_agent: Keyword.get(opts, :child_agent, nil)
    }

    system_prompt = Prompts.system_prompt(config)
    Map.put(config, :system_prompt, system_prompt)
  end

  defp resolve_model_spec(model) when is_atom(model) do
    Jido.AI.resolve_model(model)
  end

  defp resolve_model_spec(model) when is_binary(model) do
    model
  end

  defp normalize_action({inner, _meta}), do: normalize_action(inner)
  defp normalize_action(action), do: action

  defp to_machine_msg(@start, %{query: query}) do
    call_id = Machine.generate_call_id()
    {:start, query, call_id}
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

  defp to_machine_msg(_, _), do: nil

  defp store_context(%{context: context}, config) when is_binary(context) do
    request_id = Jido.Util.generate_id()

    {:ok, ref} =
      ContextStore.put(context, request_id, inline_threshold: config[:context_inline_threshold])

    ref
  end

  defp set_run_tool_context(agent, context) when is_map(context) do
    state = StratState.get(agent, %{})
    new_state = Map.put(state, :run_tool_context, context)
    StratState.put(agent, new_state)
  end

  defp store_rlm_state(agent, %{query: query, context_ref: context_ref, workspace_ref: workspace_ref}) do
    state = StratState.get(agent, %{})

    new_state =
      state
      |> Map.put(:query, query)
      |> Map.put(:context_ref, context_ref)
      |> Map.put(:workspace_ref, workspace_ref)

    StratState.put(agent, new_state)
  end

  defp get_workspace_summary(state) do
    case state[:workspace_ref] do
      nil -> ""
      ref -> WorkspaceStore.summary(ref)
    end
  end

  defp maybe_finalize(state, status) when status in [:completed, :error] do
    final_summary =
      case state[:workspace_ref] do
        nil -> ""
        ref -> WorkspaceStore.summary(ref)
      end

    cleanup_rlm_state(state)

    state
    |> Map.put(:final_workspace_summary, final_summary)
    |> Map.delete(:run_tool_context)
    |> Map.delete(:context_ref)
    |> Map.delete(:workspace_ref)
  end

  defp maybe_finalize(state, _status), do: state

  defp filter_tools_for_depth(tools, current_depth, max_depth) when current_depth >= max_depth do
    Enum.reject(tools, fn tool -> tool.name == "rlm_spawn_agent" end)
  end

  defp filter_tools_for_depth(tools, _current_depth, _max_depth), do: tools

  defp cleanup_rlm_state(state) do
    if state[:context_ref], do: ContextStore.delete(state[:context_ref])
    if state[:workspace_ref], do: WorkspaceStore.delete(state[:workspace_ref])
  end
end
