defmodule Jido.AI.Reasoning.TreeOfThoughts.Strategy do
  @moduledoc """
  Tree-of-Thoughts (ToT) execution strategy for Jido agents.

  This strategy implements branching exploration by generating multiple candidate
  thoughts at each step, evaluating them, and expanding the most promising branches.

  ## Overview

  Tree-of-Thoughts extends Chain-of-Thought by:
  - Generating multiple candidate thoughts at each step
  - Evaluating each thought's potential
  - Exploring promising branches while pruning poor ones
  - Supporting different traversal strategies (BFS, DFS, best-first)

  This approach is effective for problems requiring search, like:
  - Puzzles and games
  - Planning and scheduling
  - Creative writing
  - Complex reasoning tasks

  ## Architecture

  This strategy uses a pure state machine (`Jido.AI.Reasoning.TreeOfThoughts.Machine`) for
  all state transitions. The strategy acts as a thin adapter that:
  - Converts instructions to machine messages
  - Converts machine directives to SDK-specific directive structs
  - Manages the machine state within the agent

  ## Configuration

  Configure via strategy options when defining your agent:

      use Jido.Agent,
        name: "my_tot_agent",
        strategy: {
          Jido.AI.Reasoning.TreeOfThoughts.Strategy,
          model: "anthropic:claude-sonnet-4-20250514",
          branching_factor: 3,
          max_depth: 4,
          traversal_strategy: :best_first
        }

  ### Options

  - `:model` (optional) - Model identifier, defaults to "anthropic:claude-haiku-4-5"
  - `:branching_factor`, `:max_depth`, `:traversal_strategy` (optional) - Core tree search controls
  - `:top_k`, `:min_depth`, `:max_nodes`, `:max_duration_ms`, `:beam_width` (optional) - Search budget and shaping controls
  - `:early_success_threshold`, `:convergence_window`, `:min_score_improvement`, `:max_parse_retries` (optional) - Completion/parser controls
  - `:tools`, `:tool_context`, `:tool_timeout_ms`, `:tool_max_retries`, `:tool_retry_backoff_ms`, `:max_tool_round_trips` (optional) - Tool execution controls
  - `:generation_prompt` (optional) - Custom prompt for thought generation
  - `:evaluation_prompt` (optional) - Custom prompt for thought evaluation

  ## Signal Routing

  This strategy implements `signal_routes/1` which AgentServer uses to
  automatically route these signals to strategy commands:

  - `"ai.tot.query"` → `:tot_start`
  - `"ai.llm.response"` → `:tot_llm_result`
  - `"ai.llm.delta"` → `:tot_llm_partial`

  ## State

  State is stored under `agent.state.__strategy__` with tree structure.
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Directive
  alias Jido.AI.Reasoning.Helpers
  alias Jido.AI.Reasoning.TreeOfThoughts.Machine
  alias Jido.AI.ToolAdapter
  alias Jido.AI.Turn
  alias ReqLLM.Context

  @type config :: %{
          model: String.t(),
          branching_factor: pos_integer(),
          max_depth: pos_integer(),
          traversal_strategy: Machine.traversal_strategy(),
          generation_prompt: String.t(),
          evaluation_prompt: String.t(),
          top_k: pos_integer(),
          min_depth: non_neg_integer(),
          max_nodes: pos_integer(),
          max_duration_ms: pos_integer() | nil,
          beam_width: pos_integer() | nil,
          early_success_threshold: float(),
          convergence_window: pos_integer(),
          min_score_improvement: float(),
          max_parse_retries: non_neg_integer(),
          tools: [module()],
          actions_by_name: %{String.t() => module()},
          reqllm_tools: [ReqLLM.Tool.t()],
          tool_context: map(),
          tool_timeout_ms: pos_integer(),
          tool_max_retries: non_neg_integer(),
          tool_retry_backoff_ms: non_neg_integer(),
          max_tool_round_trips: pos_integer()
        }

  @default_model "anthropic:claude-haiku-4-5"
  @default_top_k 3
  @default_min_depth 2
  @default_max_nodes 100
  @default_early_success_threshold 1.0
  @default_convergence_window 2
  @default_min_score_improvement 0.02
  @default_max_parse_retries 1
  @default_tool_timeout_ms 15_000
  @default_tool_max_retries 1
  @default_tool_retry_backoff_ms 200
  @default_max_tool_round_trips 3

  @start :tot_start
  @llm_result :tot_llm_result
  @llm_partial :tot_llm_partial
  @request_error :tot_request_error
  @tool_result :tot_tool_result

  @doc "Returns the action atom for starting a ToT exploration."
  @spec start_action() :: :tot_start
  def start_action, do: @start

  @doc "Returns the action atom for handling LLM results."
  @spec llm_result_action() :: :tot_llm_result
  def llm_result_action, do: @llm_result

  @doc "Returns the action atom for handling streaming LLM partial tokens."
  @spec llm_partial_action() :: :tot_llm_partial
  def llm_partial_action, do: @llm_partial

  @doc "Returns the action atom for handling request rejection events."
  @spec request_error_action() :: :tot_request_error
  def request_error_action, do: @request_error

  @doc "Returns the action atom for handling tool result events."
  @spec tool_result_action() :: :tot_tool_result
  def tool_result_action, do: @tool_result

  @action_specs %{
    @start => %{
      schema: Zoi.object(%{prompt: Zoi.string(), request_id: Zoi.string() |> Zoi.optional()}),
      doc: "Start a new Tree-of-Thoughts exploration",
      name: "tot.start"
    },
    @llm_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), result: Zoi.any()}),
      doc: "Handle LLM response",
      name: "tot.llm_result"
    },
    @llm_partial => %{
      schema:
        Zoi.object(%{
          call_id: Zoi.string(),
          delta: Zoi.string(),
          chunk_type: Zoi.atom() |> Zoi.default(:content)
        }),
      doc: "Handle streaming LLM token chunk",
      name: "tot.llm_partial"
    },
    @request_error => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string(),
          reason: Zoi.atom(),
          message: Zoi.string()
        }),
      doc: "Handle rejected request lifecycle event",
      name: "tot.request_error"
    },
    @tool_result => %{
      schema:
        Zoi.object(%{
          call_id: Zoi.string(),
          tool_name: Zoi.string(),
          result: Zoi.any()
        }),
      doc: "Handle completed tool execution for ToT tool round",
      name: "tot.tool_result"
    }
  }

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"ai.tot.query", {:strategy_cmd, @start}},
      {"ai.llm.response", {:strategy_cmd, @llm_result}},
      {"ai.llm.delta", {:strategy_cmd, @llm_partial}},
      {"ai.tool.result", {:strategy_cmd, @tool_result}},
      {"ai.request.error", {:strategy_cmd, @request_error}},
      # Usage report is emitted for observability but doesn't need processing
      {"ai.usage", Jido.Actions.Control.Noop}
    ]
  end

  @impl true
  def snapshot(%Agent{} = agent, _ctx) do
    state = StratState.get(agent, %{})
    status = map_status(state[:status])

    %Jido.Agent.Strategy.Snapshot{
      status: status,
      done?: status in [:success, :failure],
      result: state[:result],
      details: build_details(state)
    }
  end

  defp map_status(:completed), do: :success
  defp map_status(:error), do: :failure
  defp map_status(:idle), do: :idle
  defp map_status(_), do: :running

  defp build_details(state) do
    result = state[:result]

    %{
      phase: state[:status],
      node_count: map_size(state[:nodes] || %{}),
      current_depth: get_current_depth(state),
      max_depth: state[:max_depth],
      branching_factor: state[:branching_factor],
      traversal_strategy: state[:traversal_strategy],
      solution_path: state[:solution_path],
      frontier_size: length(state[:frontier] || []),
      usage: state[:usage],
      duration_ms: calculate_duration(state[:started_at]),
      top_k: state[:top_k],
      diagnostics: if(is_map(result), do: result[:diagnostics], else: nil),
      best_candidate: if(is_map(result), do: result[:best], else: nil)
    }
    |> Enum.reject(fn {_k, v} -> empty_value?(v) end)
    |> Map.new()
  end

  defp get_current_depth(state) do
    case state[:current_node_id] do
      nil ->
        0

      node_id ->
        nodes = state[:nodes] || %{}

        case Map.get(nodes, node_id) do
          nil -> 0
          node -> node.depth
        end
    end
  end

  defp empty_value?(nil), do: true
  defp empty_value?(""), do: true
  defp empty_value?([]), do: true
  defp empty_value?(map) when map == %{}, do: true
  defp empty_value?(0), do: false
  defp empty_value?(_), do: false

  defp calculate_duration(nil), do: nil
  defp calculate_duration(started_at), do: System.monotonic_time(:millisecond) - started_at

  @impl true
  def init(%Agent{} = agent, ctx) do
    config = build_config(agent, ctx)

    machine =
      Machine.new(
        branching_factor: config.branching_factor,
        max_depth: config.max_depth,
        traversal_strategy: config.traversal_strategy,
        top_k: config.top_k,
        min_depth: config.min_depth,
        max_nodes: config.max_nodes,
        max_duration_ms: config.max_duration_ms,
        beam_width: config.beam_width,
        early_success_threshold: config.early_success_threshold,
        convergence_window: config.convergence_window,
        min_score_improvement: config.min_score_improvement,
        max_parse_retries: config.max_parse_retries
      )

    state =
      machine
      |> Machine.to_map()
      |> Map.merge(%{
        tool_rounds: %{},
        pending_tool_calls: %{},
        pending_tool_results: %{},
        llm_call_aliases: %{},
        pending_tool_phase: nil,
        pending_tool_call_id: nil,
        pending_tool_turn: nil
      })
      |> Helpers.apply_to_state([Helpers.update_config(config)])

    agent = StratState.put(agent, state)
    {agent, []}
  end

  @impl true
  def cmd(%Agent{} = agent, instructions, ctx) do
    {agent, dirs_rev} =
      Enum.reduce(instructions, {agent, []}, fn instr, {acc_agent, acc_dirs} ->
        case process_instruction(acc_agent, instr, ctx) do
          {new_agent, new_dirs} ->
            {new_agent, Enum.reverse(new_dirs, acc_dirs)}

          :noop ->
            {acc_agent, acc_dirs}
        end
      end)

    {agent, Enum.reverse(dirs_rev)}
  end

  defp process_instruction(agent, %Jido.Instruction{action: action, params: params} = instruction, ctx) do
    normalized_action = normalize_action(action)

    state = StratState.get(agent, %{})
    config = state[:config] || %{}

    case normalized_action do
      @request_error ->
        process_request_error(agent, params)

      @llm_result ->
        process_llm_result(agent, params, config, ctx)

      @tool_result ->
        process_tool_result(agent, params, config)

      _ ->
        case to_machine_msg(normalized_action, params) do
          msg when not is_nil(msg) ->
            apply_machine_update(agent, msg, config)

          _ ->
            Helpers.maybe_execute_action_instruction(agent, instruction, ctx)
        end
    end
  end

  defp normalize_action({inner, _meta}), do: normalize_action(inner)
  defp normalize_action(action), do: action

  defp to_machine_msg(@start, %{prompt: prompt} = params) do
    request_id =
      case Map.get(params, :request_id) do
        id when is_binary(id) -> id
        _ -> generate_call_id()
      end

    {:start, prompt, request_id}
  end

  defp to_machine_msg(@llm_result, %{call_id: call_id, result: result}) do
    {:llm_result, call_id, result}
  end

  defp to_machine_msg(@llm_partial, %{call_id: call_id, delta: delta, chunk_type: chunk_type}) do
    {:llm_partial, call_id, delta, chunk_type}
  end

  defp to_machine_msg(_, _), do: nil

  defp process_request_error(agent, %{request_id: request_id, reason: reason, message: message}) do
    state = StratState.get(agent, %{})
    new_state = Map.put(state, :last_request_error, %{request_id: request_id, reason: reason, message: message})
    agent = StratState.put(agent, new_state)
    {agent, []}
  end

  defp process_request_error(_, _), do: :noop

  defp process_llm_result(agent, %{call_id: call_id, result: result}, config, _ctx) when is_binary(call_id) do
    state = StratState.get(agent, %{})

    cond do
      has_pending_tool_round?(state, call_id) ->
        apply_machine_update(agent, {:llm_result, call_id, result}, config)

      tooling_enabled?(config) and llm_turn_needs_tools?(result) ->
        start_tool_round(agent, state, call_id, result, config)

      true ->
        apply_machine_update(agent, {:llm_result, call_id, result}, config)
    end
  end

  defp process_llm_result(agent, _params, config, _ctx) do
    apply_machine_update(agent, nil, config)
  end

  defp process_tool_result(agent, %{call_id: tool_call_id} = params, config) when is_binary(tool_call_id) do
    state = StratState.get(agent, %{})
    pending_calls = state[:pending_tool_calls] || %{}

    case Map.fetch(pending_calls, tool_call_id) do
      :error ->
        {agent, []}

      {:ok, _pending} ->
        pending_results =
          Map.put(
            state[:pending_tool_results] || %{},
            tool_call_id,
            %{result: params[:result], tool_name: params[:tool_name]}
          )

        state = Map.put(state, :pending_tool_results, pending_results)

        if pending_tool_round_complete?(state) do
          resume_after_tool_round(agent, state, config)
        else
          {StratState.put(agent, state), []}
        end
    end
  end

  defp process_tool_result(agent, _params, _config), do: {agent, []}

  defp apply_machine_update(agent, nil, _config), do: {agent, []}

  defp apply_machine_update(agent, msg, config) do
    state = StratState.get(agent, %{})
    machine = Machine.from_map(state)

    env = %{
      generation_prompt: config[:generation_prompt],
      evaluation_prompt: config[:evaluation_prompt]
    }

    {machine, directives} = Machine.update(machine, msg, env)
    {lifted_directives, call_aliases} = lift_directives(directives, config)

    new_state =
      state
      |> preserve_machine_extras()
      |> Map.merge(Machine.to_map(machine))
      |> Map.update(:llm_call_aliases, call_aliases, &Map.merge(&1, call_aliases))
      |> maybe_attach_tool_diagnostics()
      |> Helpers.apply_to_state([Helpers.update_config(config)])

    agent = StratState.put(agent, new_state)
    {agent, lifted_directives}
  end

  defp preserve_machine_extras(state) do
    Map.take(state, [
      :tool_rounds,
      :pending_tool_calls,
      :pending_tool_results,
      :llm_call_aliases,
      :pending_tool_phase,
      :pending_tool_call_id,
      :pending_tool_turn
    ])
  end

  defp maybe_attach_tool_diagnostics(state) do
    result = state[:result]

    if is_map(result) do
      updated_result =
        result
        |> Map.update(:diagnostics, %{tool_rounds: state[:tool_rounds] || %{}}, fn diagnostics ->
          Map.put(diagnostics || %{}, :tool_rounds, state[:tool_rounds] || %{})
        end)

      Map.put(state, :result, updated_result)
    else
      state
    end
  end

  defp tooling_enabled?(config) do
    is_list(config[:reqllm_tools]) and config[:reqllm_tools] != [] and is_map(config[:actions_by_name])
  end

  defp llm_turn_needs_tools?(result) do
    result
    |> Turn.from_result_map()
    |> Turn.needs_tools?()
  rescue
    _ -> false
  end

  defp start_tool_round(agent, state, llm_call_id, result, config) do
    turn = Turn.from_result_map(result)
    normalized_calls = normalize_tool_calls(turn.tool_calls)
    round = get_in(state, [:tool_rounds, llm_call_id]) || 0
    max_round_trips = config[:max_tool_round_trips] || 3

    cond do
      normalized_calls == [] ->
        apply_machine_update(agent, {:llm_result, llm_call_id, result}, config)

      round >= max_round_trips ->
        apply_machine_update(agent, {:llm_result, llm_call_id, {:error, :max_tool_round_trips_reached}}, config)

      true ->
        request_id = state[:last_request_id]
        iteration = state[:iteration] || 0

        directives =
          Enum.map(normalized_calls, fn call ->
            case Map.get(config[:actions_by_name] || %{}, call.tool_name) do
              nil ->
                Directive.EmitToolError.new!(%{
                  id: call.call_id,
                  tool_name: call.tool_name,
                  error: %{type: :not_found, message: "Tool not found: #{call.tool_name}"}
                })

              module ->
                Directive.ToolExec.new!(%{
                  id: call.call_id,
                  tool_name: call.tool_name,
                  action_module: module,
                  arguments: call.arguments,
                  context:
                    Map.merge(config[:tool_context] || %{}, %{
                      agent_id: agent.id,
                      request_id: request_id,
                      iteration: iteration
                    }),
                  timeout_ms: config[:tool_timeout_ms],
                  max_retries: config[:tool_max_retries],
                  retry_backoff_ms: config[:tool_retry_backoff_ms],
                  request_id: request_id,
                  iteration: iteration
                })
            end
          end)

        pending_tool_calls = Map.new(normalized_calls, fn call -> {call.call_id, call} end)

        new_state =
          state
          |> Map.put(:pending_tool_calls, pending_tool_calls)
          |> Map.put(:pending_tool_results, %{})
          |> Map.put(:pending_tool_call_id, llm_call_id)
          |> Map.put(:pending_tool_turn, turn)
          |> Map.put(:pending_tool_phase, state[:status])
          |> Map.update(:tool_rounds, %{llm_call_id => round + 1}, fn rounds ->
            Map.put(rounds || %{}, llm_call_id, round + 1)
          end)

        {StratState.put(agent, new_state), directives}
    end
  rescue
    _ ->
      apply_machine_update(agent, {:llm_result, llm_call_id, result}, config)
  end

  defp has_pending_tool_round?(state, llm_call_id) do
    state[:pending_tool_call_id] == llm_call_id and map_size(state[:pending_tool_calls] || %{}) > 0
  end

  defp pending_tool_round_complete?(state) do
    pending_calls = Map.keys(state[:pending_tool_calls] || %{})
    completed = Map.keys(state[:pending_tool_results] || %{})
    pending_calls != [] and Enum.all?(pending_calls, &(&1 in completed))
  end

  defp resume_after_tool_round(agent, state, config) do
    llm_call_id = state[:pending_tool_call_id]
    turn = state[:pending_tool_turn] |> then(&(&1 || %{})) |> Turn.from_result_map()
    pending_calls = state[:pending_tool_calls] || %{}
    pending_results = state[:pending_tool_results] || %{}
    base_context = get_in(state, [:llm_call_aliases, llm_call_id]) || []

    tool_results =
      pending_calls
      |> Map.values()
      |> Enum.map(fn call ->
        result_entry = pending_results[call.call_id] || %{}

        %{
          id: call.call_id,
          name: call.tool_name,
          raw_result: result_entry[:result] || {:error, :missing_tool_result}
        }
      end)

    turn_with_results = Turn.with_tool_results(turn, tool_results)

    followup_context =
      base_context ++
        [Turn.assistant_message(turn)] ++
        Turn.tool_messages(turn_with_results)

    directive =
      Directive.LLMStream.new!(%{
        id: llm_call_id,
        model: config[:model],
        context: convert_to_reqllm_context(followup_context),
        tools: config[:reqllm_tools] || []
      })

    new_state =
      state
      |> Map.put(:pending_tool_calls, %{})
      |> Map.put(:pending_tool_results, %{})
      |> Map.put(:pending_tool_phase, nil)
      |> Map.put(:pending_tool_call_id, nil)
      |> Map.put(:pending_tool_turn, nil)
      |> Map.update(:llm_call_aliases, %{}, &Map.put(&1, llm_call_id, followup_context))

    {StratState.put(agent, new_state), [directive]}
  end

  defp normalize_tool_calls(tool_calls) when is_list(tool_calls) do
    Enum.map(tool_calls, fn tool_call ->
      %{
        call_id: extract_tool_call_id(tool_call),
        tool_name: extract_tool_call_name(tool_call),
        arguments: extract_tool_call_arguments(tool_call)
      }
    end)
    |> Enum.filter(&(is_binary(&1.call_id) and is_binary(&1.tool_name)))
  end

  defp extract_tool_call_id(%ReqLLM.ToolCall{id: id}) when is_binary(id), do: id
  defp extract_tool_call_id(%{id: id}) when is_binary(id), do: id
  defp extract_tool_call_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_tool_call_id(_), do: nil

  defp extract_tool_call_name(%ReqLLM.ToolCall{} = call), do: ReqLLM.ToolCall.name(call)
  defp extract_tool_call_name(%{name: name}) when is_binary(name), do: name
  defp extract_tool_call_name(%{"name" => name}) when is_binary(name), do: name
  defp extract_tool_call_name(%{function: %{name: name}}) when is_binary(name), do: name
  defp extract_tool_call_name(%{"function" => %{"name" => name}}) when is_binary(name), do: name
  defp extract_tool_call_name(_), do: nil

  defp extract_tool_call_arguments(%ReqLLM.ToolCall{} = call), do: ReqLLM.ToolCall.args_map(call)
  defp extract_tool_call_arguments(%{arguments: args}) when is_map(args), do: args
  defp extract_tool_call_arguments(%{"arguments" => args}) when is_map(args), do: args
  defp extract_tool_call_arguments(%{function: %{arguments: args}}) when is_binary(args), do: decode_json_map(args)

  defp extract_tool_call_arguments(%{"function" => %{"arguments" => args}}) when is_binary(args),
    do: decode_json_map(args)

  defp extract_tool_call_arguments(_), do: %{}

  defp decode_json_map(binary) do
    case Jason.decode(binary) do
      {:ok, %{} = decoded} -> decoded
      _ -> %{}
    end
  end

  defp lift_directives(directives, config) do
    %{model: model} = config

    {lifted, call_aliases} =
      Enum.reduce(directives, {[], %{}}, fn
        {:generate_thoughts, id, conversation, _count}, {acc_dirs, aliases} ->
          directive = build_llm_directive(id, model, conversation, config, llm_tools_for_request(config))

          {[directive | acc_dirs], Map.put(aliases, id, conversation)}

        {:evaluate_thoughts, id, thoughts}, {acc_dirs, aliases} ->
          context = build_evaluation_context(thoughts, config)

          directive = build_llm_directive(id, model, context, config, llm_tools_for_request(config))

          {[directive | acc_dirs], Map.put(aliases, id, context)}

        {:call_llm_stream, id, conversation}, {acc_dirs, aliases} ->
          directive = build_llm_directive(id, model, conversation, config, [])

          {[directive | acc_dirs], Map.put(aliases, id, conversation)}

        {:request_error, request_id, reason, message}, {acc_dirs, aliases} ->
          directive =
            Directive.EmitRequestError.new!(%{
              request_id: request_id,
              reason: reason,
              message: message
            })

          {[directive | acc_dirs], aliases}
      end)

    {Enum.reverse(lifted), call_aliases}
  end

  defp build_llm_directive(call_id, model, conversation, config, tools) do
    attrs = %{
      id: call_id,
      model: model,
      context: convert_to_reqllm_context(conversation),
      tools: tools
    }

    attrs =
      case config[:max_duration_ms] do
        timeout when is_integer(timeout) and timeout > 0 -> Map.put(attrs, :timeout, timeout)
        _ -> attrs
      end

    Directive.LLMStream.new!(attrs)
  end

  defp llm_tools_for_request(config) do
    if tooling_enabled?(config), do: config[:reqllm_tools] || [], else: []
  end

  defp build_evaluation_context(thoughts, config) do
    system_prompt = config[:evaluation_prompt] || Machine.default_evaluation_prompt()

    thoughts_text =
      thoughts
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn
        {%{id: id, content: content}, idx} ->
          "#{idx}. #{id}: #{content}"

        {%{"id" => id, "content" => content}, idx} ->
          "#{idx}. #{id}: #{content}"

        {thought, idx} when is_binary(thought) ->
          "#{idx}. t#{idx}: #{thought}"

        {_thought, idx} ->
          "#{idx}. t#{idx}:"
      end)

    [
      %{role: :system, content: system_prompt},
      %{role: :user, content: "Evaluate these thought approaches:\n\n#{thoughts_text}"}
    ]
  end

  defp convert_to_reqllm_context(conversation) do
    case Context.normalize(conversation, validate: false) do
      {:ok, context} -> Context.to_list(context)
      _ -> conversation
    end
  end

  defp build_config(agent, ctx) do
    opts = ctx[:strategy_opts] || []
    tool_context_opt = normalize_map_opt(Keyword.get(opts, :tool_context, %{}))
    tools_modules = normalize_tools_modules(Keyword.get(opts, :tools, []))
    actions_by_name = ToolAdapter.to_action_map(tools_modules)
    reqllm_tools = ToolAdapter.from_actions(Map.values(actions_by_name))

    # Resolve model
    raw_model = Map.get(agent.state, :model, Keyword.get(opts, :model, @default_model))
    resolved_model = resolve_model_spec(raw_model)

    %{
      model: resolved_model,
      branching_factor: Map.get(agent.state, :branching_factor, Keyword.get(opts, :branching_factor, 3)),
      max_depth: Map.get(agent.state, :max_depth, Keyword.get(opts, :max_depth, 3)),
      traversal_strategy:
        Map.get(agent.state, :traversal_strategy, Keyword.get(opts, :traversal_strategy, :best_first)),
      generation_prompt:
        Map.get(
          agent.state,
          :generation_prompt,
          Keyword.get(opts, :generation_prompt, Machine.default_generation_prompt())
        ),
      evaluation_prompt:
        Map.get(
          agent.state,
          :evaluation_prompt,
          Keyword.get(opts, :evaluation_prompt, Machine.default_evaluation_prompt())
        ),
      top_k: Map.get(agent.state, :top_k, Keyword.get(opts, :top_k, @default_top_k)),
      min_depth: Map.get(agent.state, :min_depth, Keyword.get(opts, :min_depth, @default_min_depth)),
      max_nodes: Map.get(agent.state, :max_nodes, Keyword.get(opts, :max_nodes, @default_max_nodes)),
      max_duration_ms: Map.get(agent.state, :max_duration_ms, Keyword.get(opts, :max_duration_ms)),
      beam_width: Map.get(agent.state, :beam_width, Keyword.get(opts, :beam_width)),
      early_success_threshold:
        Map.get(
          agent.state,
          :early_success_threshold,
          Keyword.get(opts, :early_success_threshold, @default_early_success_threshold)
        ),
      convergence_window:
        Map.get(
          agent.state,
          :convergence_window,
          Keyword.get(opts, :convergence_window, @default_convergence_window)
        ),
      min_score_improvement:
        Map.get(
          agent.state,
          :min_score_improvement,
          Keyword.get(opts, :min_score_improvement, @default_min_score_improvement)
        ),
      max_parse_retries:
        Map.get(agent.state, :max_parse_retries, Keyword.get(opts, :max_parse_retries, @default_max_parse_retries)),
      tools: Map.values(actions_by_name),
      actions_by_name: actions_by_name,
      reqllm_tools: reqllm_tools,
      tool_context: Map.get(agent.state, :tool_context) || tool_context_opt,
      tool_timeout_ms: Keyword.get(opts, :tool_timeout_ms, @default_tool_timeout_ms),
      tool_max_retries: Keyword.get(opts, :tool_max_retries, @default_tool_max_retries),
      tool_retry_backoff_ms: Keyword.get(opts, :tool_retry_backoff_ms, @default_tool_retry_backoff_ms),
      max_tool_round_trips: Keyword.get(opts, :max_tool_round_trips, @default_max_tool_round_trips)
    }
  end

  defp resolve_model_spec(model) when is_atom(model) do
    Jido.AI.resolve_model(model)
  end

  defp resolve_model_spec(model) when is_binary(model) do
    model
  end

  defp normalize_tools_modules(modules) when is_list(modules) do
    modules
    |> Enum.filter(&is_atom/1)
    |> Enum.uniq()
  end

  defp normalize_tools_modules(module) when is_atom(module), do: [module]
  defp normalize_tools_modules(_), do: []

  defp normalize_map_opt(%{} = value), do: value
  defp normalize_map_opt({:%{}, _meta, pairs}) when is_list(pairs), do: Map.new(pairs)
  defp normalize_map_opt(_), do: %{}

  defp generate_call_id, do: Machine.generate_call_id()

  @doc """
  Returns all nodes in the tree.
  """
  @spec get_nodes(Agent.t()) :: %{String.t() => Machine.thought_node()}
  def get_nodes(%Agent{} = agent) do
    state = StratState.get(agent, %{})
    state[:nodes] || %{}
  end

  @doc """
  Returns the solution path (list of node IDs from root to solution).
  """
  @spec get_solution_path(Agent.t()) :: [String.t()]
  def get_solution_path(%Agent{} = agent) do
    state = StratState.get(agent, %{})
    state[:solution_path] || []
  end

  @doc """
  Returns the solution content (the result).
  """
  @spec get_result(Agent.t()) :: map() | nil
  def get_result(%Agent{} = agent) do
    state = StratState.get(agent, %{})
    state[:result]
  end

  @doc """
  Returns the best scoring node in the tree.
  """
  @spec get_best_node(Agent.t()) :: Machine.thought_node() | nil
  def get_best_node(%Agent{} = agent) do
    state = StratState.get(agent, %{})
    machine = Machine.from_map(state)
    Machine.find_best_leaf(machine)
  end
end
