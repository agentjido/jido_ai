defmodule Jido.AI.Strategies.TreeOfThoughts do
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

  This strategy uses a pure state machine (`Jido.AI.TreeOfThoughts.Machine`) for
  all state transitions. The strategy acts as a thin adapter that:
  - Converts instructions to machine messages
  - Converts machine directives to SDK-specific directive structs
  - Manages the machine state within the agent

  ## Configuration

  Configure via strategy options when defining your agent:

      use Jido.Agent,
        name: "my_tot_agent",
        strategy: {
          Jido.AI.Strategies.TreeOfThoughts,
          model: "anthropic:claude-sonnet-4-20250514",
          branching_factor: 3,
          max_depth: 4,
          traversal_strategy: :best_first
        }

  ### Options

  - `:model` (optional) - Model identifier, defaults to "anthropic:claude-haiku-4-5"
  - `:branching_factor` (optional) - Number of thoughts per node, defaults to 3
  - `:max_depth` (optional) - Maximum tree depth, defaults to 3
  - `:traversal_strategy` (optional) - `:bfs`, `:dfs`, or `:best_first`, defaults to `:best_first`
  - `:generation_prompt` (optional) - Custom prompt for thought generation
  - `:evaluation_prompt` (optional) - Custom prompt for thought evaluation

  ## Signal Routing

  This strategy implements `signal_routes/1` which AgentServer uses to
  automatically route these signals to strategy commands:

  - `"tot.query"` → `:tot_start`
  - `"reqllm.result"` → `:tot_llm_result`
  - `"reqllm.partial"` → `:tot_llm_partial`

  ## State

  State is stored under `agent.state.__strategy__` with tree structure.
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Config
  alias Jido.AI.Directive
  alias Jido.AI.Strategy.StateOpsHelpers
  alias Jido.AI.TreeOfThoughts.Machine
  alias ReqLLM.Context

  @type config :: %{
          model: String.t(),
          branching_factor: pos_integer(),
          max_depth: pos_integer(),
          traversal_strategy: Machine.traversal_strategy(),
          generation_prompt: String.t(),
          evaluation_prompt: String.t()
        }

  @default_model "anthropic:claude-haiku-4-5"

  @start :tot_start
  @llm_result :tot_llm_result
  @llm_partial :tot_llm_partial

  @doc "Returns the action atom for starting a ToT exploration."
  @spec start_action() :: :tot_start
  def start_action, do: @start

  @doc "Returns the action atom for handling LLM results."
  @spec llm_result_action() :: :tot_llm_result
  def llm_result_action, do: @llm_result

  @doc "Returns the action atom for handling streaming LLM partial tokens."
  @spec llm_partial_action() :: :tot_llm_partial
  def llm_partial_action, do: @llm_partial

  @action_specs %{
    @start => %{
      schema: Zoi.object(%{prompt: Zoi.string()}),
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
    }
  }

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"tot.query", {:strategy_cmd, @start}},
      {"reqllm.result", {:strategy_cmd, @llm_result}},
      {"reqllm.partial", {:strategy_cmd, @llm_partial}}
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
      duration_ms: calculate_duration(state[:started_at])
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
        traversal_strategy: config.traversal_strategy
      )

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
    case to_machine_msg(normalize_action(action), params) do
      msg when not is_nil(msg) ->
        state = StratState.get(agent, %{})
        config = state[:config]
        machine = Machine.from_map(state)

        env = %{
          generation_prompt: config[:generation_prompt],
          evaluation_prompt: config[:evaluation_prompt]
        }

        {machine, directives} = Machine.update(machine, msg, env)

        new_state =
          machine
          |> Machine.to_map()
          |> StateOpsHelpers.apply_to_state([StateOpsHelpers.update_config(config)])

        agent = StratState.put(agent, new_state)
        {agent, lift_directives(directives, config)}

      _ ->
        :noop
    end
  end

  defp normalize_action({inner, _meta}), do: normalize_action(inner)
  defp normalize_action(action), do: action

  defp to_machine_msg(@start, %{prompt: prompt}) do
    call_id = generate_call_id()
    {:start, prompt, call_id}
  end

  defp to_machine_msg(@llm_result, %{call_id: call_id, result: result}) do
    {:llm_result, call_id, result}
  end

  defp to_machine_msg(@llm_partial, %{call_id: call_id, delta: delta, chunk_type: chunk_type}) do
    {:llm_partial, call_id, delta, chunk_type}
  end

  defp to_machine_msg(_, _), do: nil

  defp lift_directives(directives, config) do
    %{model: model} = config

    Enum.flat_map(directives, fn
      {:generate_thoughts, id, conversation, _count} ->
        [
          Directive.ReqLLMStream.new!(%{
            id: id,
            model: model,
            context: convert_to_reqllm_context(conversation),
            tools: []
          })
        ]

      {:evaluate_thoughts, id, thoughts} ->
        context = build_evaluation_context(thoughts, config)

        [
          Directive.ReqLLMStream.new!(%{
            id: id,
            model: model,
            context: convert_to_reqllm_context(context),
            tools: []
          })
        ]

      {:call_llm_stream, id, conversation} ->
        [
          Directive.ReqLLMStream.new!(%{
            id: id,
            model: model,
            context: convert_to_reqllm_context(conversation),
            tools: []
          })
        ]
    end)
  end

  defp build_evaluation_context(thoughts, config) do
    system_prompt = config[:evaluation_prompt] || Machine.default_evaluation_prompt()

    thoughts_text =
      thoughts
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {thought, idx} -> "#{idx}. #{thought}" end)

    [
      %{role: :system, content: system_prompt},
      %{role: :user, content: "Evaluate these thought approaches:\n\n#{thoughts_text}"}
    ]
  end

  defp convert_to_reqllm_context(conversation) do
    {:ok, context} = Context.normalize(conversation, validate: false)
    Context.to_list(context)
  end

  defp build_config(agent, ctx) do
    opts = ctx[:strategy_opts] || []

    # Resolve model
    raw_model = Keyword.get(opts, :model, Map.get(agent.state, :model, @default_model))
    resolved_model = resolve_model_spec(raw_model)

    %{
      model: resolved_model,
      branching_factor: Keyword.get(opts, :branching_factor, 3),
      max_depth: Keyword.get(opts, :max_depth, 3),
      traversal_strategy: Keyword.get(opts, :traversal_strategy, :best_first),
      generation_prompt: Keyword.get(opts, :generation_prompt, Machine.default_generation_prompt()),
      evaluation_prompt: Keyword.get(opts, :evaluation_prompt, Machine.default_evaluation_prompt())
    }
  end

  defp resolve_model_spec(model) when is_atom(model) do
    Config.resolve_model(model)
  end

  defp resolve_model_spec(model) when is_binary(model) do
    model
  end

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
  @spec get_result(Agent.t()) :: String.t() | nil
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
