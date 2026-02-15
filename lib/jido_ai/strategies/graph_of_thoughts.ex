defmodule Jido.AI.Strategies.GraphOfThoughts do
  @moduledoc """
  Graph-of-Thoughts (GoT) execution strategy for Jido agents.

  This strategy implements graph-based reasoning by generating thoughts as nodes,
  finding connections between them, and aggregating multiple thoughts into conclusions.

  ## Overview

  Graph-of-Thoughts extends Tree-of-Thoughts by:
  - Allowing nodes to have multiple parents (graph vs tree)
  - Supporting thought aggregation and synthesis
  - Finding connections between disparate thoughts
  - Enabling more complex reasoning patterns

  This approach is effective for problems requiring:
  - Multi-perspective analysis
  - Synthesis of competing ideas
  - Complex causal reasoning
  - Knowledge integration

  ## Architecture

  This strategy uses a pure state machine (`Jido.AI.GraphOfThoughts.Machine`) for
  all state transitions. The strategy acts as a thin adapter that:
  - Converts instructions to machine messages
  - Converts machine directives to SDK-specific directive structs
  - Manages the machine state within the agent

  ## Configuration

  Configure via strategy options when defining your agent:

      use Jido.Agent,
        name: "my_got_agent",
        strategy: {
          Jido.AI.Strategies.GraphOfThoughts,
          model: "anthropic:claude-sonnet-4-20250514",
          max_nodes: 20,
          max_depth: 5,
          aggregation_strategy: :synthesis
        }

  ### Options

  - `:model` (optional) - Model identifier, defaults to "anthropic:claude-haiku-4-5"
  - `:max_nodes` (optional) - Maximum number of nodes, defaults to 20
  - `:max_depth` (optional) - Maximum graph depth, defaults to 5
  - `:aggregation_strategy` (optional) - `:voting`, `:weighted`, or `:synthesis`, defaults to `:synthesis`
  - `:generation_prompt` (optional) - Custom prompt for thought generation
  - `:connection_prompt` (optional) - Custom prompt for finding connections
  - `:aggregation_prompt` (optional) - Custom prompt for aggregation

  ## Signal Routing

  This strategy implements `signal_routes/1` which AgentServer uses to
  automatically route these signals to strategy commands:

  - `"ai.got.query"` → `:got_start`
  - `"ai.llm.response"` → `:got_llm_result`
  - `"ai.llm.delta"` → `:got_llm_partial`

  ## State

  State is stored under `agent.state.__strategy__` with graph structure.
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Directive
  alias Jido.AI.GraphOfThoughts.Machine
  alias Jido.AI.Strategy.StateOpsHelpers
  alias ReqLLM.Context

  @default_model "anthropic:claude-haiku-4-5"

  @start :got_start
  @llm_result :got_llm_result
  @llm_partial :got_llm_partial
  @request_error :got_request_error

  @doc "Returns the action atom for starting a GoT exploration."
  @spec start_action() :: :got_start
  def start_action, do: @start

  @doc "Returns the action atom for handling LLM results."
  @spec llm_result_action() :: :got_llm_result
  def llm_result_action, do: @llm_result

  @doc "Returns the action atom for handling streaming LLM partial tokens."
  @spec llm_partial_action() :: :got_llm_partial
  def llm_partial_action, do: @llm_partial

  @doc "Returns the action atom for handling request rejection events."
  @spec request_error_action() :: :got_request_error
  def request_error_action, do: @request_error

  @action_specs %{
    @start => %{
      schema: Zoi.object(%{prompt: Zoi.string(), request_id: Zoi.string() |> Zoi.optional()}),
      doc: "Start a new Graph-of-Thoughts exploration",
      name: "got.start"
    },
    @llm_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), result: Zoi.any()}),
      doc: "Handle LLM response",
      name: "got.llm_result"
    },
    @llm_partial => %{
      schema:
        Zoi.object(%{
          call_id: Zoi.string(),
          delta: Zoi.string(),
          chunk_type: Zoi.atom() |> Zoi.default(:content)
        }),
      doc: "Handle streaming LLM token chunk",
      name: "got.llm_partial"
    },
    @request_error => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string(),
          reason: Zoi.atom(),
          message: Zoi.string()
        }),
      doc: "Handle rejected request lifecycle event",
      name: "got.request_error"
    }
  }

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"ai.got.query", {:strategy_cmd, @start}},
      {"ai.llm.response", {:strategy_cmd, @llm_result}},
      {"ai.llm.delta", {:strategy_cmd, @llm_partial}},
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
    %{
      phase: state[:status],
      node_count: map_size(state[:nodes] || %{}),
      edge_count: length(state[:edges] || []),
      current_node_id: state[:current_node_id],
      max_nodes: state[:max_nodes],
      max_depth: state[:max_depth],
      aggregation_strategy: state[:aggregation_strategy],
      usage: state[:usage],
      duration_ms: calculate_duration(state[:started_at])
    }
    |> Enum.reject(fn {_k, v} -> empty_value?(v) end)
    |> Map.new()
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
        max_nodes: config.max_nodes,
        max_depth: config.max_depth,
        aggregation_strategy: config.aggregation_strategy
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

  # Public Helpers

  @doc """
  Gets all nodes from the agent's GoT state.
  """
  @spec get_nodes(Agent.t()) :: [Machine.thought_node()]
  def get_nodes(agent) do
    state = StratState.get(agent, %{})
    machine = Machine.from_map(state)
    Machine.get_nodes(machine)
  end

  @doc """
  Gets all edges from the agent's GoT state.
  """
  @spec get_edges(Agent.t()) :: [Machine.edge()]
  def get_edges(agent) do
    state = StratState.get(agent, %{})
    machine = Machine.from_map(state)
    machine.edges
  end

  @doc """
  Gets the result from a completed GoT exploration.
  """
  @spec get_result(Agent.t()) :: term() | nil
  def get_result(agent) do
    state = StratState.get(agent, %{})
    machine = Machine.from_map(state)
    machine.result
  end

  @doc """
  Gets the best leaf node from the agent's GoT state.
  """
  @spec get_best_node(Agent.t()) :: Machine.thought_node() | nil
  def get_best_node(agent) do
    state = StratState.get(agent, %{})
    machine = Machine.from_map(state)
    Machine.find_best_leaf(machine)
  end

  @doc """
  Traces the solution path from root to best leaf.
  """
  @spec get_solution_path(Agent.t()) :: [String.t()]
  def get_solution_path(agent) do
    state = StratState.get(agent, %{})
    machine = Machine.from_map(state)
    best = Machine.find_best_leaf(machine)

    if best do
      Machine.trace_path(machine, best.id)
    else
      []
    end
  end

  # Private Helpers

  defp build_config(agent, ctx) do
    opts = ctx[:strategy_opts] || []

    # Resolve model
    raw_model = Keyword.get(opts, :model, Map.get(agent.state, :model, @default_model))
    resolved_model = resolve_model_spec(raw_model)

    %{
      model: resolved_model,
      max_nodes: Keyword.get(opts, :max_nodes, 20),
      max_depth: Keyword.get(opts, :max_depth, 5),
      aggregation_strategy: Keyword.get(opts, :aggregation_strategy, :synthesis),
      generation_prompt: Keyword.get(opts, :generation_prompt, Machine.default_generation_prompt()),
      connection_prompt: Keyword.get(opts, :connection_prompt, Machine.default_connection_prompt()),
      aggregation_prompt: Keyword.get(opts, :aggregation_prompt, Machine.default_aggregation_prompt())
    }
  end

  defp resolve_model_spec(model) when is_atom(model) do
    Jido.AI.resolve_model(model)
  end

  defp resolve_model_spec(model) when is_binary(model) do
    model
  end

  defp process_instruction(agent, %{action: @start, params: params}) do
    state = StratState.get(agent, %{})
    machine = Machine.from_map(state)

    prompt = Map.get(params, :prompt) || Map.get(params, "prompt")
    request_id = Map.get(params, :request_id) || Map.get(params, "request_id") || Machine.generate_call_id()

    {updated_machine, directives} = Machine.update(machine, {:start, prompt, request_id}, %{})
    lifted = lift_directives(directives, state)

    updated_state =
      updated_machine
      |> Machine.to_map()
      |> StateOpsHelpers.apply_to_state([StateOpsHelpers.update_config(state[:config])])

    updated_agent = StratState.put(agent, updated_state)
    {updated_agent, lifted}
  end

  defp process_instruction(agent, %{action: @llm_result, params: params}) do
    state = StratState.get(agent, %{})
    machine = Machine.from_map(state)

    call_id = Map.get(params, :call_id) || Map.get(params, "call_id")
    result = Map.get(params, :result) || Map.get(params, "result")

    {updated_machine, directives} = Machine.update(machine, {:llm_result, call_id, result}, %{})
    lifted = lift_directives(directives, state)

    updated_state =
      updated_machine
      |> Machine.to_map()
      |> StateOpsHelpers.apply_to_state([StateOpsHelpers.update_config(state[:config])])

    updated_agent = StratState.put(agent, updated_state)
    {updated_agent, lifted}
  end

  defp process_instruction(agent, %{action: @llm_partial, params: params}) do
    state = StratState.get(agent, %{})
    machine = Machine.from_map(state)

    call_id = Map.get(params, :call_id) || Map.get(params, "call_id")
    delta = Map.get(params, :delta) || Map.get(params, "delta")
    chunk_type = Map.get(params, :chunk_type) || Map.get(params, "chunk_type") || :content

    {updated_machine, directives} =
      Machine.update(machine, {:llm_partial, call_id, delta, chunk_type}, %{})

    lifted = lift_directives(directives, state)

    updated_state =
      updated_machine
      |> Machine.to_map()
      |> StateOpsHelpers.apply_to_state([StateOpsHelpers.update_config(state[:config])])

    updated_agent = StratState.put(agent, updated_state)
    {updated_agent, lifted}
  end

  defp process_instruction(agent, %{action: @request_error, params: params}) do
    request_id = Map.get(params, :request_id) || Map.get(params, "request_id")
    reason = Map.get(params, :reason) || Map.get(params, "reason")
    message = Map.get(params, :message) || Map.get(params, "message")

    if is_binary(request_id) do
      state = StratState.get(agent, %{})
      new_state = Map.put(state, :last_request_error, %{request_id: request_id, reason: reason, message: message})
      {StratState.put(agent, new_state), []}
    else
      :noop
    end
  end

  defp process_instruction(_agent, _instruction), do: :noop

  defp lift_directives(directives, state) do
    config = Map.get(state, :config, %{})
    %{model: model} = config

    Enum.flat_map(directives, fn
      {:generate_thought, id, context} ->
        [build_generate_directive(id, context, model, config)]

      {:find_connections, id, _node_id, context} ->
        [build_connection_directive(id, context, model, config)]

      {:aggregate, id, _node_ids, context} ->
        [build_aggregation_directive(id, context, model, config)]

      {:completed, _result} ->
        # Completion is handled in state, no directive needed
        []

      # Issue #9 fix: Handle request rejection when agent is busy
      {:request_error, request_id, reason, message} ->
        [
          Directive.EmitRequestError.new!(%{
            request_id: request_id,
            reason: reason,
            message: message
          })
        ]

      _ ->
        []
    end)
  end

  defp build_generate_directive(id, context, model, config) do
    system = Map.get(context, :system_prompt, config.generation_prompt)

    user =
      if context[:context] && context[:context] != "" do
        """
        Original problem: #{context[:prompt]}

        Previous reasoning:
        #{context[:context]}

        Current thought to expand:
        #{context[:current_thought]}

        Please continue the reasoning from this point.
        """
      else
        """
        Problem: #{context[:prompt]}

        #{context[:current_thought]}

        Please analyze this and provide your reasoning.
        """
      end

    messages = [
      %{role: :system, content: system},
      %{role: :user, content: user}
    ]

    Directive.LLMStream.new!(%{
      id: id,
      model: model,
      context: convert_to_reqllm_context(messages),
      tools: []
    })
  end

  defp build_connection_directive(id, context, model, config) do
    system = Map.get(context, :system_prompt, config.connection_prompt)

    user = """
    Here are the thoughts in the graph:

    #{context[:nodes]}

    Identify meaningful connections between these thoughts.
    Format each connection as: CONNECTION: [node_id] -> [node_id] : [relationship]
    """

    messages = [
      %{role: :system, content: system},
      %{role: :user, content: user}
    ]

    Directive.LLMStream.new!(%{
      id: id,
      model: model,
      context: convert_to_reqllm_context(messages),
      tools: []
    })
  end

  defp build_aggregation_directive(id, context, model, config) do
    system = Map.get(context, :system_prompt, config.aggregation_prompt)

    user = """
    Original problem: #{context[:prompt]}

    Here are the thoughts to synthesize:

    #{context[:thoughts]}

    Please synthesize these into a coherent conclusion.
    """

    messages = [
      %{role: :system, content: system},
      %{role: :user, content: user}
    ]

    Directive.LLMStream.new!(%{
      id: id,
      model: model,
      context: convert_to_reqllm_context(messages),
      tools: []
    })
  end

  defp convert_to_reqllm_context(conversation) do
    {:ok, context} = Context.normalize(conversation, validate: false)
    Context.to_list(context)
  end
end
