defmodule Jido.AI.GraphOfThoughts.Machine do
  @moduledoc """
  Pure state machine for the Graph-of-Thoughts (GoT) reasoning pattern.

  This module implements state transitions for a GoT agent without any side effects.
  It uses Fsmx for state machine management and returns directives that describe
  what external effects should be performed.

  ## Overview

  Graph-of-Thoughts extends Tree-of-Thoughts by allowing nodes to have multiple
  parents and supporting merging/aggregation of thoughts. This enables more complex
  reasoning patterns like combining insights from different branches.

  ## States

  - `:idle` - Initial state, waiting for a prompt
  - `:generating` - Generating a thought for the current context
  - `:connecting` - Finding connections between nodes
  - `:aggregating` - Aggregating multiple nodes into one
  - `:completed` - Final state, solution found
  - `:error` - Error state

  ## Graph Structure

  The graph is stored as nodes and edges:

      %{
        nodes: %{
          "node_1" => %{
            id: "node_1",
            content: "Initial problem...",
            score: nil,
            depth: 0,
            metadata: %{}
          },
          ...
        },
        edges: [
          %{from: "node_1", to: "node_2", type: :generates},
          %{from: "node_2", to: "node_3", type: :refines},
          ...
        ]
      }

  ## Edge Types

  - `:generates` - Parent thought generates child thought
  - `:refines` - Refinement of existing thought
  - `:aggregates` - Multiple thoughts aggregated into one
  - `:connects` - Conceptual connection between thoughts

  ## Usage

  The machine is used by the GoT strategy:

      machine = Machine.new()
      {machine, directives} = Machine.update(machine, {:start, prompt, call_id}, env)

  All state transitions are pure - side effects are described in directives.

  ## Status Type Boundary

  **Internal (Machine struct):** Status is stored as strings (`"idle"`, `"completed"`)
  due to Fsmx library requirements.

  **External (Strategy state, Snapshots):** Status is converted to atoms (`:idle`,
  `:completed`) via `to_map/1` before storage in agent state.

  Never compare `machine.status` directly with atoms - use `Machine.to_map/1` first.
  """

  use Fsmx.Struct,
    state_field: :status,
    transitions: %{
      "idle" => ["generating"],
      "generating" => ["connecting", "aggregating", "completed", "error"],
      "connecting" => ["generating", "aggregating", "completed", "error"],
      "aggregating" => ["generating", "connecting", "completed", "error"],
      "completed" => [],
      "error" => []
    }

  # Telemetry event names
  @telemetry_prefix [:jido, :ai, :got]

  @typedoc "Internal machine status (string) - required by Fsmx library"
  @type internal_status :: String.t()

  @typedoc "External status (atom) - used in strategy state after to_map/1 conversion"
  @type external_status :: :idle | :generating | :connecting | :aggregating | :completed | :error

  @type termination_reason :: :success | :error | :max_nodes | :max_depth | nil
  @type aggregation_strategy :: :voting | :weighted | :synthesis
  @type edge_type :: :generates | :refines | :aggregates | :connects

  @type thought_node :: %{
          id: String.t(),
          content: String.t(),
          score: float() | nil,
          depth: non_neg_integer(),
          metadata: map()
        }

  @type edge :: %{
          from: String.t(),
          to: String.t(),
          type: edge_type()
        }

  @type usage :: %{
          optional(:input_tokens) => non_neg_integer(),
          optional(:output_tokens) => non_neg_integer(),
          optional(:total_tokens) => non_neg_integer()
        }

  @type t :: %__MODULE__{
          status: internal_status(),
          prompt: String.t() | nil,
          nodes: %{String.t() => thought_node()},
          edges: [edge()],
          root_id: String.t() | nil,
          current_node_id: String.t() | nil,
          pending_operation: atom() | nil,
          pending_node_ids: [String.t()],
          result: term(),
          current_call_id: String.t() | nil,
          termination_reason: termination_reason(),
          streaming_text: String.t(),
          usage: usage(),
          started_at: integer() | nil,
          max_nodes: pos_integer(),
          max_depth: pos_integer(),
          aggregation_strategy: aggregation_strategy(),
          generation_count: non_neg_integer()
        }

  defstruct status: "idle",
            prompt: nil,
            nodes: %{},
            edges: [],
            root_id: nil,
            current_node_id: nil,
            pending_operation: nil,
            pending_node_ids: [],
            result: nil,
            current_call_id: nil,
            termination_reason: nil,
            streaming_text: "",
            usage: %{},
            started_at: nil,
            max_nodes: 20,
            max_depth: 5,
            aggregation_strategy: :synthesis,
            generation_count: 0

  @doc """
  Creates a new machine with default state.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      max_nodes: Keyword.get(opts, :max_nodes, 20),
      max_depth: Keyword.get(opts, :max_depth, 5),
      aggregation_strategy: Keyword.get(opts, :aggregation_strategy, :synthesis)
    }
  end

  @doc """
  Updates the machine state based on an incoming message.

  Returns `{updated_machine, directives}` where directives describe
  external effects to perform.

  ## Messages

  - `{:start, prompt, call_id}` - Start GoT reasoning
  - `{:llm_result, call_id, result}` - Handle LLM response
  - `{:llm_partial, call_id, delta, chunk_type}` - Handle streaming
  """
  @spec update(t(), term(), map()) :: {t(), list()}
  def update(machine, message, env \\ %{})

  def update(%__MODULE__{status: "idle"} = machine, {:start, prompt, call_id}, _env) do
    emit_telemetry(:start, %{prompt_length: String.length(prompt)})

    with_transition(machine, "generating", fn machine ->
      # Create root node
      root_id = generate_node_id()

      root_node = %{
        id: root_id,
        content: prompt,
        score: nil,
        depth: 0,
        metadata: %{type: :root}
      }

      machine =
        machine
        |> Map.put(:prompt, prompt)
        |> Map.put(:nodes, %{root_id => root_node})
        |> Map.put(:root_id, root_id)
        |> Map.put(:current_node_id, root_id)
        |> Map.put(:current_call_id, call_id)
        |> Map.put(:started_at, System.monotonic_time(:millisecond))
        |> Map.put(:streaming_text, "")
        |> Map.put(:generation_count, 1)

      context = build_generation_context(machine, root_id)

      {machine, [{:generate_thought, call_id, context}]}
    end)
  end

  # Issue #3 fix: Explicitly reject start requests when busy instead of silently dropping
  def update(%__MODULE__{status: status} = machine, {:start, _prompt, call_id}, _env)
      when status in ["generating", "connecting", "aggregating"] do
    {machine, [{:request_error, call_id, :busy, "Agent is busy (status: #{status})"}]}
  end

  def update(%__MODULE__{} = machine, {:llm_result, call_id, result}, env) do
    if call_id == machine.current_call_id do
      handle_llm_result(machine, result, env)
    else
      # Stale call_id, ignore
      {machine, []}
    end
  end

  def update(%__MODULE__{} = machine, {:llm_partial, call_id, delta, chunk_type}, _env) do
    if call_id == machine.current_call_id do
      handle_llm_partial(machine, delta, chunk_type)
    else
      {machine, []}
    end
  end

  def update(%__MODULE__{} = machine, {:thought_generated, call_id, content}, env) do
    if call_id == machine.current_call_id do
      handle_thought_generated(machine, content, env)
    else
      {machine, []}
    end
  end

  def update(%__MODULE__{} = machine, {:connections_found, call_id, connections}, env) do
    if call_id == machine.current_call_id do
      handle_connections_found(machine, connections, env)
    else
      {machine, []}
    end
  end

  def update(%__MODULE__{} = machine, {:aggregation_complete, call_id, result}, env) do
    if call_id == machine.current_call_id do
      handle_aggregation_complete(machine, result, env)
    else
      {machine, []}
    end
  end

  def update(%__MODULE__{} = machine, {:error, reason}, _env) do
    handle_error(machine, reason)
  end

  def update(%__MODULE__{} = machine, _message, _env) do
    {machine, []}
  end

  # Graph Operations

  @doc """
  Adds a node to the graph.
  """
  @spec add_node(t(), thought_node()) :: t()
  def add_node(%__MODULE__{nodes: nodes} = machine, node) do
    %{machine | nodes: Map.put(nodes, node.id, node)}
  end

  @doc """
  Adds an edge between two nodes.
  """
  @spec add_edge(t(), String.t(), String.t(), edge_type()) :: t()
  def add_edge(%__MODULE__{edges: edges} = machine, from_id, to_id, type) do
    edge = %{from: from_id, to: to_id, type: type}
    %{machine | edges: [edge | edges]}
  end

  @doc """
  Gets a node by ID.
  """
  @spec get_node(t(), String.t()) :: thought_node() | nil
  def get_node(%__MODULE__{nodes: nodes}, node_id) do
    Map.get(nodes, node_id)
  end

  @doc """
  Gets all nodes in the graph.
  """
  @spec get_nodes(t()) :: [thought_node()]
  def get_nodes(%__MODULE__{nodes: nodes}) do
    Map.values(nodes)
  end

  @doc """
  Gets all edges from a node.
  """
  @spec get_outgoing_edges(t(), String.t()) :: [edge()]
  def get_outgoing_edges(%__MODULE__{edges: edges}, node_id) do
    Enum.filter(edges, &(&1.from == node_id))
  end

  @doc """
  Gets all edges to a node.
  """
  @spec get_incoming_edges(t(), String.t()) :: [edge()]
  def get_incoming_edges(%__MODULE__{edges: edges}, node_id) do
    Enum.filter(edges, &(&1.to == node_id))
  end

  @doc """
  Gets all child node IDs for a node.
  """
  @spec get_children(t(), String.t()) :: [String.t()]
  def get_children(machine, node_id) do
    machine
    |> get_outgoing_edges(node_id)
    |> Enum.map(& &1.to)
  end

  @doc """
  Gets all parent node IDs for a node.
  """
  @spec get_parents(t(), String.t()) :: [String.t()]
  def get_parents(machine, node_id) do
    machine
    |> get_incoming_edges(node_id)
    |> Enum.map(& &1.from)
  end

  @doc """
  Gets all ancestor node IDs (parents, grandparents, etc.).
  """
  @spec get_ancestors(t(), String.t()) :: [String.t()]
  def get_ancestors(machine, node_id) do
    get_ancestors_recursive(machine, node_id, MapSet.new())
    |> MapSet.to_list()
  end

  @spec get_ancestors_recursive(t(), String.t(), MapSet.t(String.t())) :: MapSet.t(String.t())
  defp get_ancestors_recursive(machine, node_id, visited) do
    parents = get_parents(machine, node_id)

    Enum.reduce(parents, visited, fn parent_id, acc ->
      if MapSet.member?(acc, parent_id) do
        acc
      else
        acc
        |> MapSet.put(parent_id)
        |> then(&get_ancestors_recursive(machine, parent_id, &1))
      end
    end)
  end

  @doc """
  Gets all descendant node IDs (children, grandchildren, etc.).
  """
  @spec get_descendants(t(), String.t()) :: [String.t()]
  def get_descendants(machine, node_id) do
    get_descendants_recursive(machine, node_id, MapSet.new())
    |> MapSet.to_list()
  end

  @spec get_descendants_recursive(t(), String.t(), MapSet.t(String.t())) :: MapSet.t(String.t())
  defp get_descendants_recursive(machine, node_id, visited) do
    children = get_children(machine, node_id)

    Enum.reduce(children, visited, fn child_id, acc ->
      if MapSet.member?(acc, child_id) do
        acc
      else
        acc
        |> MapSet.put(child_id)
        |> then(&get_descendants_recursive(machine, child_id, &1))
      end
    end)
  end

  @doc """
  Detects if there's a cycle in the graph.
  """
  @spec has_cycle?(t()) :: boolean()
  def has_cycle?(%__MODULE__{nodes: nodes} = machine) do
    node_ids = Map.keys(nodes)
    initial_path = []
    Enum.any?(node_ids, &cycle_from_node?(machine, &1, initial_path))
  end

  @spec cycle_from_node?(t(), String.t(), [String.t()]) :: boolean()
  defp cycle_from_node?(machine, node_id, path) do
    if node_id in path do
      true
    else
      new_path = [node_id | path]
      children = get_children(machine, node_id)
      Enum.any?(children, &cycle_from_node?(machine, &1, new_path))
    end
  end

  @doc """
  Finds all leaf nodes (nodes with no outgoing edges).
  """
  @spec find_leaves(t()) :: [thought_node()]
  def find_leaves(%__MODULE__{nodes: nodes} = machine) do
    nodes
    |> Map.values()
    |> Enum.filter(fn node ->
      get_outgoing_edges(machine, node.id) == []
    end)
  end

  @doc """
  Finds the best leaf node by score.
  """
  @spec find_best_leaf(t()) :: thought_node() | nil
  def find_best_leaf(machine) do
    machine
    |> find_leaves()
    |> Enum.filter(&(not is_nil(&1.score)))
    |> Enum.max_by(& &1.score, fn -> nil end)
  end

  @doc """
  Traces the path from root to a node.
  """
  @spec trace_path(t(), String.t()) :: [String.t()]
  def trace_path(%__MODULE__{root_id: root_id} = machine, node_id) do
    trace_path_recursive(machine, node_id, root_id, [])
  end

  defp trace_path_recursive(_machine, current_id, current_id, path) do
    [current_id | path]
  end

  defp trace_path_recursive(machine, node_id, root_id, path) do
    parents = get_parents(machine, node_id)

    case parents do
      [] ->
        # No parents, we're at a root
        [node_id | path]

      [parent_id | _] ->
        # Follow first parent (for graphs with multiple parents, this gets one path)
        trace_path_recursive(machine, parent_id, root_id, [node_id | path])
    end
  end

  @doc """
  Returns the current status as an atom.
  """
  @spec status(t()) :: external_status()
  def status(%__MODULE__{status: status}) do
    status_to_atom(status)
  end

  defp status_to_atom("idle"), do: :idle
  defp status_to_atom("generating"), do: :generating
  defp status_to_atom("connecting"), do: :connecting
  defp status_to_atom("aggregating"), do: :aggregating
  defp status_to_atom("completed"), do: :completed
  defp status_to_atom("error"), do: :error
  defp status_to_atom(status) when is_atom(status), do: status

  @doc """
  Converts the machine state to a map suitable for strategy state storage.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = machine) do
    machine
    |> Map.from_struct()
    |> Map.update!(:status, &status_to_atom/1)
  end

  # Module attribute for valid struct keys
  @from_map_defaults %{
    nodes: %{},
    edges: [],
    pending_node_ids: [],
    streaming_text: "",
    usage: %{},
    max_nodes: 20,
    max_depth: 5,
    aggregation_strategy: :synthesis,
    generation_count: 0
  }

  @struct_keys [
    :status,
    :prompt,
    :nodes,
    :edges,
    :root_id,
    :current_node_id,
    :pending_operation,
    :pending_node_ids,
    :result,
    :current_call_id,
    :termination_reason,
    :streaming_text,
    :usage,
    :started_at,
    :max_nodes,
    :max_depth,
    :aggregation_strategy,
    :generation_count
  ]

  @doc """
  Creates a machine from a map (e.g., from strategy state storage).
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    merged = Map.merge(@from_map_defaults, map)
    filtered = Map.take(merged, @struct_keys)

    struct!(__MODULE__, Map.put(filtered, :status, normalize_status(merged[:status])))
  end

  defp normalize_status(s) when is_atom(s) and not is_nil(s), do: Atom.to_string(s)
  defp normalize_status(s) when is_binary(s), do: s
  defp normalize_status(_), do: "idle"

  @doc """
  Generates a unique node ID.
  """
  @spec generate_node_id() :: String.t()
  def generate_node_id do
    "got_node_#{Jido.Util.generate_id()}"
  end

  @doc """
  Generates a unique call ID for LLM requests.
  """
  @spec generate_call_id() :: String.t()
  def generate_call_id do
    "got_#{Jido.Util.generate_id()}"
  end

  @doc """
  Returns the default system prompt for thought generation.
  """
  @spec default_generation_prompt() :: String.t()
  def default_generation_prompt do
    """
    You are a reasoning assistant that explores problems through graph-based thinking.
    Your task is to generate a thoughtful response that:
    1. Analyzes the given context
    2. Identifies key concepts and relationships
    3. Proposes a clear line of reasoning

    Be specific and constructive. Focus on insights that can connect to other thoughts.
    """
  end

  @doc """
  Returns the default prompt for finding connections.
  """
  @spec default_connection_prompt() :: String.t()
  def default_connection_prompt do
    """
    You are analyzing thoughts to find connections between them.
    Given the following thoughts, identify which ones are related and how.

    For each connection found, respond in the format:
    CONNECTION: [node_id_1] -> [node_id_2] : [relationship description]

    Focus on meaningful conceptual connections, not superficial similarities.
    """
  end

  @doc """
  Returns the default prompt for aggregation.
  """
  @spec default_aggregation_prompt() :: String.t()
  def default_aggregation_prompt do
    """
    You are synthesizing multiple thoughts into a coherent conclusion.
    Given the following thoughts, create a unified response that:
    1. Incorporates the key insights from each thought
    2. Resolves any contradictions
    3. Provides a clear, actionable conclusion

    Respond with your synthesized conclusion.
    """
  end

  # Private Helpers

  defp with_transition(machine, new_status, fun) do
    case Fsmx.transition(machine, new_status, state_field: :status) do
      {:ok, machine} -> fun.(machine)
      {:error, _} -> {machine, []}
    end
  end

  defp handle_llm_result(%__MODULE__{status: "generating"} = machine, {:ok, result}, env) do
    machine = accumulate_usage(machine, result)
    content = extract_content(result)
    handle_thought_generated(machine, content, env)
  end

  defp handle_llm_result(%__MODULE__{status: "connecting"} = machine, {:ok, result}, env) do
    machine = accumulate_usage(machine, result)
    content = extract_content(result)
    connections = parse_connections(content)
    handle_connections_found(machine, connections, env)
  end

  defp handle_llm_result(%__MODULE__{status: "aggregating"} = machine, {:ok, result}, env) do
    machine = accumulate_usage(machine, result)
    content = extract_content(result)
    handle_aggregation_complete(machine, content, env)
  end

  defp handle_llm_result(machine, {:error, reason}, _env) do
    handle_error(machine, reason)
  end

  defp handle_llm_result(machine, _result, _env) do
    {machine, []}
  end

  defp handle_llm_partial(machine, delta, _chunk_type) do
    machine = Map.update!(machine, :streaming_text, &(&1 <> (delta || "")))
    {machine, []}
  end

  defp handle_thought_generated(machine, content, env) do
    current_node = get_node(machine, machine.current_node_id)
    current_depth = current_node.depth

    # Create new node for the generated thought
    node_id = generate_node_id()

    new_node = %{
      id: node_id,
      content: content,
      score: nil,
      depth: current_depth + 1,
      metadata: %{type: :thought}
    }

    machine =
      machine
      |> add_node(new_node)
      |> add_edge(machine.current_node_id, node_id, :generates)
      |> Map.put(:streaming_text, "")

    # Check termination conditions
    cond do
      map_size(machine.nodes) >= machine.max_nodes ->
        complete_with_best_result(machine, :max_nodes)

      current_depth + 1 >= machine.max_depth ->
        complete_with_best_result(machine, :max_depth)

      should_aggregate?(machine, env) ->
        start_aggregation(machine, node_id, env)

      should_find_connections?(machine, env) ->
        start_connection_finding(machine, node_id, env)

      true ->
        continue_generation(machine, node_id, env)
    end
  end

  defp handle_connections_found(machine, connections, env) do
    # Add edges for each connection found
    machine =
      Enum.reduce(connections, machine, fn {from_id, to_id, _desc}, m ->
        if get_node(m, from_id) && get_node(m, to_id) do
          add_edge(m, from_id, to_id, :connects)
        else
          m
        end
      end)

    # After finding connections, either aggregate or continue
    if should_aggregate?(machine, env) do
      node_ids = Map.keys(machine.nodes)
      start_aggregation_on_nodes(machine, node_ids, env)
    else
      # Continue with the most recent node
      leaves = find_leaves(machine)

      case leaves do
        [] ->
          complete_with_best_result(machine, :success)

        [leaf | _] ->
          continue_generation(machine, leaf.id, env)
      end
    end
  end

  defp handle_aggregation_complete(machine, result, _env) do
    # Create aggregation result node
    node_id = generate_node_id()

    aggregated_node = %{
      id: node_id,
      content: result,
      score: 1.0,
      depth: machine.max_depth,
      metadata: %{type: :aggregation, source_nodes: machine.pending_node_ids}
    }

    machine =
      machine
      |> add_node(aggregated_node)
      |> Map.put(:streaming_text, "")

    # Add edges from source nodes to aggregated node
    machine =
      Enum.reduce(machine.pending_node_ids, machine, fn source_id, m ->
        add_edge(m, source_id, node_id, :aggregates)
      end)

    complete_with_result(machine, result)
  end

  defp handle_error(machine, reason) do
    case Fsmx.transition(machine, "error", state_field: :status) do
      {:ok, machine} ->
        machine =
          machine
          |> Map.put(:result, {:error, reason})
          |> Map.put(:termination_reason, :error)

        emit_telemetry(:error, %{reason: reason})
        {machine, []}

      {:error, _} ->
        {machine, []}
    end
  end

  defp should_aggregate?(machine, env) do
    # Aggregate when we have enough nodes or explicitly requested
    node_count = map_size(machine.nodes)
    min_for_aggregation = Map.get(env, :min_nodes_for_aggregation, 3)

    node_count >= min_for_aggregation and machine.generation_count >= 2
  end

  defp should_find_connections?(machine, _env) do
    # Find connections after generating multiple nodes
    node_count = map_size(machine.nodes)
    node_count >= 2 and machine.generation_count >= 1 and rem(machine.generation_count, 2) == 0
  end

  defp start_aggregation(machine, current_node_id, env) do
    # Get all leaf nodes for aggregation
    leaves = find_leaves(machine)
    leaf_ids = Enum.map(leaves, & &1.id) |> Enum.take(5)

    node_ids =
      if current_node_id in leaf_ids do
        leaf_ids
      else
        [current_node_id | leaf_ids] |> Enum.take(5)
      end

    start_aggregation_on_nodes(machine, node_ids, env)
  end

  defp start_aggregation_on_nodes(machine, node_ids, _env) do
    with_transition(machine, "aggregating", fn machine ->
      call_id = generate_call_id()

      machine =
        machine
        |> Map.put(:current_call_id, call_id)
        |> Map.put(:pending_operation, :aggregate)
        |> Map.put(:pending_node_ids, node_ids)
        |> Map.put(:streaming_text, "")

      context = build_aggregation_context(machine, node_ids)

      {machine, [{:aggregate, call_id, node_ids, context}]}
    end)
  end

  defp start_connection_finding(machine, current_node_id, _env) do
    with_transition(machine, "connecting", fn machine ->
      call_id = generate_call_id()

      machine =
        machine
        |> Map.put(:current_call_id, call_id)
        |> Map.put(:pending_operation, :find_connections)
        |> Map.put(:current_node_id, current_node_id)
        |> Map.put(:streaming_text, "")

      context = build_connection_context(machine)

      {machine, [{:find_connections, call_id, current_node_id, context}]}
    end)
  end

  defp continue_generation(machine, node_id, _env) do
    # Stay in generating state or transition back to it
    machine =
      if machine.status == "generating" do
        machine
      else
        case Fsmx.transition(machine, "generating", state_field: :status) do
          {:ok, m} -> m
          {:error, _} -> machine
        end
      end

    call_id = generate_call_id()

    machine =
      machine
      |> Map.put(:current_node_id, node_id)
      |> Map.put(:current_call_id, call_id)
      |> Map.put(:streaming_text, "")
      |> Map.update!(:generation_count, &(&1 + 1))

    context = build_generation_context(machine, node_id)

    {machine, [{:generate_thought, call_id, context}]}
  end

  defp complete_with_best_result(machine, reason) do
    best_leaf = find_best_leaf(machine)

    result =
      if best_leaf do
        best_leaf.content
      else
        # Fall back to most recent node
        leaves = find_leaves(machine)

        case leaves do
          [leaf | _] -> leaf.content
          [] -> machine.prompt
        end
      end

    complete_with_result(Map.put(machine, :termination_reason, reason), result)
  end

  defp complete_with_result(machine, result) do
    case Fsmx.transition(machine, "completed", state_field: :status) do
      {:ok, machine} ->
        duration = System.monotonic_time(:millisecond) - (machine.started_at || 0)

        machine =
          machine
          |> Map.put(:result, result)
          |> Map.put(:termination_reason, machine.termination_reason || :success)

        emit_telemetry(:complete, %{
          duration_ms: duration,
          node_count: map_size(machine.nodes),
          edge_count: length(machine.edges),
          termination_reason: machine.termination_reason,
          usage: machine.usage
        })

        {machine, [{:completed, result}]}

      {:error, _} ->
        {machine, []}
    end
  end

  defp build_generation_context(machine, node_id) do
    node = get_node(machine, node_id)
    ancestors = get_ancestors(machine, node_id)

    ancestor_contents =
      ancestors
      |> Enum.map(&get_node(machine, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map_join("\n\n---\n\n", & &1.content)

    current_content = if node, do: node.content, else: machine.prompt

    %{
      prompt: machine.prompt,
      current_thought: current_content,
      context: ancestor_contents,
      depth: if(node, do: node.depth, else: 0),
      system_prompt: default_generation_prompt()
    }
  end

  defp build_connection_context(machine) do
    node_summaries =
      machine.nodes
      |> Map.values()
      |> Enum.map_join("\n\n", fn node ->
        "#{node.id}: #{String.slice(node.content, 0, 200)}"
      end)

    %{
      nodes: node_summaries,
      system_prompt: default_connection_prompt()
    }
  end

  defp build_aggregation_context(machine, node_ids) do
    thoughts =
      node_ids
      |> Enum.map(&get_node(machine, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map_join("\n\n---\n\n", fn node ->
        "Thought #{node.id}:\n#{node.content}"
      end)

    %{
      prompt: machine.prompt,
      thoughts: thoughts,
      node_ids: node_ids,
      system_prompt: default_aggregation_prompt()
    }
  end

  defp extract_content(%{text: text}) when is_binary(text), do: text
  defp extract_content(%{content: content}) when is_binary(content), do: content
  defp extract_content(_), do: ""

  defp parse_connections(content) do
    # Parse connections in format: CONNECTION: [node_id_1] -> [node_id_2] : [description]
    regex = ~r/CONNECTION:\s*\[([^\]]+)\]\s*->\s*\[([^\]]+)\]\s*:\s*(.+)/

    Regex.scan(regex, content)
    |> Enum.map(fn [_full, from, to, desc] ->
      {String.trim(from), String.trim(to), String.trim(desc)}
    end)
  end

  defp accumulate_usage(machine, result) do
    result_usage = Map.get(result, :usage, %{})

    new_usage =
      machine.usage
      |> Map.update(:input_tokens, result_usage[:input_tokens] || 0, fn existing ->
        existing + (result_usage[:input_tokens] || 0)
      end)
      |> Map.update(:output_tokens, result_usage[:output_tokens] || 0, fn existing ->
        existing + (result_usage[:output_tokens] || 0)
      end)

    total = Map.get(new_usage, :input_tokens, 0) + Map.get(new_usage, :output_tokens, 0)
    new_usage = Map.put(new_usage, :total_tokens, total)

    Map.put(machine, :usage, new_usage)
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      @telemetry_prefix ++ [event],
      %{system_time: System.system_time()},
      metadata
    )
  end
end
