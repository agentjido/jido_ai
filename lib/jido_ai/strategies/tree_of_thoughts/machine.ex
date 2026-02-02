defmodule Jido.AI.TreeOfThoughts.Machine do
  @moduledoc """
  Pure state machine for the Tree-of-Thoughts (ToT) reasoning pattern.

  This module implements state transitions for a ToT agent without any side effects.
  It uses Fsmx for state machine management and returns directives that describe
  what external effects should be performed.

  ## Overview

  Tree-of-Thoughts extends Chain-of-Thought by generating multiple candidate
  thoughts at each step, evaluating them, and exploring the most promising branches.
  This approach is effective for problems requiring search, like puzzles, planning,
  and creative writing.

  ## States

  - `:idle` - Initial state, waiting for a prompt
  - `:generating` - Generating candidate thoughts for current node
  - `:evaluating` - Evaluating candidate thoughts
  - `:expanding` - Selecting next node to expand
  - `:completed` - Final state, solution found
  - `:error` - Error state

  ## Tree Structure

  The tree is stored as a map of nodes:

      %{
        "node_1" => %{
          id: "node_1",
          parent_id: nil,
          content: "Initial problem...",
          score: nil,
          children: ["node_2", "node_3"],
          depth: 0
        },
        ...
      }

  ## Usage

  The machine is used by the ToT strategy:

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
      "generating" => ["evaluating", "error"],
      "evaluating" => ["expanding", "completed", "error"],
      "expanding" => ["generating", "completed", "error"],
      "completed" => [],
      "error" => []
    }

  # Telemetry event names
  @telemetry_prefix [:jido, :ai, :tot]

  @typedoc "Internal machine status (string) - required by Fsmx library"
  @type internal_status :: String.t()

  @typedoc "External status (atom) - used in strategy state after to_map/1 conversion"
  @type external_status :: :idle | :generating | :evaluating | :expanding | :completed | :error

  @type termination_reason :: :success | :error | :max_depth | nil
  @type traversal_strategy :: :bfs | :dfs | :best_first

  @type thought_node :: %{
          id: String.t(),
          parent_id: String.t() | nil,
          content: String.t(),
          score: float() | nil,
          children: [String.t()],
          depth: non_neg_integer()
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
          root_id: String.t() | nil,
          current_node_id: String.t() | nil,
          pending_thoughts: [String.t()],
          pending_scores: %{String.t() => float()},
          solution_path: [String.t()],
          result: term(),
          current_call_id: String.t() | nil,
          termination_reason: termination_reason(),
          streaming_text: String.t(),
          usage: usage(),
          started_at: integer() | nil,
          branching_factor: pos_integer(),
          max_depth: pos_integer(),
          traversal_strategy: traversal_strategy(),
          frontier: [String.t()]
        }

  defstruct status: "idle",
            prompt: nil,
            nodes: %{},
            root_id: nil,
            current_node_id: nil,
            pending_thoughts: [],
            pending_scores: %{},
            solution_path: [],
            result: nil,
            current_call_id: nil,
            termination_reason: nil,
            streaming_text: "",
            usage: %{},
            started_at: nil,
            branching_factor: 3,
            max_depth: 3,
            traversal_strategy: :best_first,
            frontier: []

  @type msg ::
          {:start, prompt :: String.t(), call_id :: String.t()}
          | {:thoughts_generated, call_id :: String.t(), thoughts :: [String.t()]}
          | {:thoughts_evaluated, call_id :: String.t(), scores :: %{String.t() => float()}}
          | {:llm_result, call_id :: String.t(), result :: term()}
          | {:llm_partial, call_id :: String.t(), delta :: String.t(), chunk_type :: atom()}

  @type directive ::
          {:generate_thoughts, id :: String.t(), context :: list(), count :: pos_integer()}
          | {:evaluate_thoughts, id :: String.t(), thoughts :: [String.t()]}
          | {:call_llm_stream, id :: String.t(), context :: list()}

  @doc """
  Creates a new machine in the idle state.

  ## Options

  - `:branching_factor` - Number of thoughts to generate at each node (default: 3)
  - `:max_depth` - Maximum depth of the tree (default: 3)
  - `:traversal_strategy` - `:bfs`, `:dfs`, or `:best_first` (default: `:best_first`)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      branching_factor: Keyword.get(opts, :branching_factor, 3),
      max_depth: Keyword.get(opts, :max_depth, 3),
      traversal_strategy: Keyword.get(opts, :traversal_strategy, :best_first)
    }
  end

  @doc """
  Updates the machine state based on a message.

  Returns the updated machine and a list of directives describing
  external effects to be performed.

  ## Messages

  - `{:start, prompt, call_id}` - Start ToT exploration
  - `{:thoughts_generated, call_id, thoughts}` - Handle generated thoughts
  - `{:thoughts_evaluated, call_id, scores}` - Handle evaluation scores
  - `{:llm_result, call_id, result}` - Handle LLM response
  - `{:llm_partial, call_id, delta, chunk_type}` - Handle streaming chunk

  ## Directives

  - `{:generate_thoughts, id, context, count}` - Request thought generation
  - `{:evaluate_thoughts, id, thoughts}` - Request thought evaluation
  - `{:call_llm_stream, id, context}` - Request LLM call
  """
  @spec update(t(), msg(), map()) :: {t(), [directive()]}
  def update(machine, msg, env \\ %{})

  def update(%__MODULE__{status: "idle"} = machine, {:start, prompt, call_id}, env) do
    started_at = System.monotonic_time(:millisecond)

    # Emit start telemetry
    emit_telemetry(:start, %{system_time: System.system_time()}, %{
      call_id: call_id,
      prompt_length: String.length(prompt),
      branching_factor: machine.branching_factor,
      max_depth: machine.max_depth,
      traversal_strategy: machine.traversal_strategy
    })

    # Create root node
    root_id = generate_node_id()

    root_node = %{
      id: root_id,
      parent_id: nil,
      content: prompt,
      score: nil,
      children: [],
      depth: 0
    }

    with_transition(machine, "generating", fn machine ->
      machine =
        machine
        |> Map.put(:prompt, prompt)
        |> Map.put(:nodes, %{root_id => root_node})
        |> Map.put(:root_id, root_id)
        |> Map.put(:current_node_id, root_id)
        |> Map.put(:current_call_id, call_id)
        |> Map.put(:termination_reason, nil)
        |> Map.put(:streaming_text, "")
        |> Map.put(:usage, %{})
        |> Map.put(:started_at, started_at)
        |> Map.put(:frontier, [])

      # Build context for thought generation
      context = build_generation_context(machine, root_id, env)

      {machine, [{:generate_thoughts, call_id, context, machine.branching_factor}]}
    end)
  end

  # Issue #3 fix: Explicitly reject start requests when busy instead of silently dropping
  def update(%__MODULE__{status: status} = machine, {:start, _prompt, call_id}, _env)
      when status in ["generating", "evaluating", "expanding"] do
    {machine, [{:request_error, call_id, :busy, "Agent is busy (status: #{status})"}]}
  end

  def update(%__MODULE__{status: "generating"} = machine, {:thoughts_generated, call_id, thoughts}, _env) do
    if call_id == machine.current_call_id do
      handle_thoughts_generated(machine, thoughts)
    else
      {machine, []}
    end
  end

  def update(%__MODULE__{status: "evaluating"} = machine, {:thoughts_evaluated, call_id, scores}, env) do
    if call_id == machine.current_call_id do
      handle_thoughts_evaluated(machine, scores, env)
    else
      {machine, []}
    end
  end

  def update(%__MODULE__{status: status} = machine, {:llm_result, call_id, result}, env)
      when status in ["generating", "evaluating"] do
    if call_id == machine.current_call_id do
      handle_llm_result(machine, result, env)
    else
      {machine, []}
    end
  end

  def update(%__MODULE__{status: status} = machine, {:llm_partial, call_id, delta, chunk_type}, _env)
      when status in ["generating", "evaluating"] do
    if call_id == machine.current_call_id do
      machine =
        case chunk_type do
          :content ->
            Map.update!(machine, :streaming_text, &(&1 <> delta))

          _ ->
            machine
        end

      {machine, []}
    else
      {machine, []}
    end
  end

  def update(machine, _msg, _env) do
    {machine, []}
  end

  @doc """
  Converts the machine state to a map suitable for strategy state storage.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = machine) do
    machine
    |> Map.from_struct()
    |> Map.update!(:status, &status_to_atom/1)
  end

  defp status_to_atom("idle"), do: :idle
  defp status_to_atom("generating"), do: :generating
  defp status_to_atom("evaluating"), do: :evaluating
  defp status_to_atom("expanding"), do: :expanding
  defp status_to_atom("completed"), do: :completed
  defp status_to_atom("error"), do: :error
  defp status_to_atom(status) when is_atom(status), do: status

  @from_map_defaults %{
    nodes: %{},
    pending_thoughts: [],
    pending_scores: %{},
    solution_path: [],
    streaming_text: "",
    usage: %{},
    branching_factor: 3,
    max_depth: 3,
    traversal_strategy: :best_first,
    frontier: []
  }

  # Keys that are valid struct fields (explicitly listed to avoid compile-time struct access)
  @struct_keys [
    :status,
    :prompt,
    :nodes,
    :root_id,
    :current_node_id,
    :pending_thoughts,
    :pending_scores,
    :solution_path,
    :result,
    :current_call_id,
    :termination_reason,
    :streaming_text,
    :usage,
    :started_at,
    :branching_factor,
    :max_depth,
    :traversal_strategy,
    :frontier
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
    "tot_node_#{Jido.Util.generate_id()}"
  end

  @doc """
  Generates a unique call ID for LLM requests.
  """
  @spec generate_call_id() :: String.t()
  def generate_call_id do
    "tot_#{Jido.Util.generate_id()}"
  end

  @doc """
  Returns the default system prompt for thought generation.
  """
  @spec default_generation_prompt() :: String.t()
  def default_generation_prompt do
    """
    You are a reasoning assistant that generates multiple distinct approaches to solve problems.

    Given a problem or partial solution, generate several different thought paths that could lead to a solution.
    Each thought should be a complete, distinct approach or next step.

    Format your response as a numbered list:
    1. [First approach/thought]
    2. [Second approach/thought]
    3. [Third approach/thought]

    Be creative and consider different angles. Each thought should be meaningfully different from the others.
    """
  end

  @doc """
  Returns the default system prompt for thought evaluation.
  """
  @spec default_evaluation_prompt() :: String.t()
  def default_evaluation_prompt do
    """
    You are a reasoning assistant that evaluates the quality of solution approaches.

    For each thought/approach, provide a score from 0.0 to 1.0 based on:
    - Correctness: Is the reasoning valid?
    - Progress: Does it move toward solving the problem?
    - Completeness: How close is it to a full solution?

    If a thought represents a complete and correct solution, give it a score of 1.0.

    Format your response as:
    1: [score] - [brief explanation]
    2: [score] - [brief explanation]
    ...
    """
  end

  @doc """
  Gets a node by ID from the machine's node map.
  """
  @spec get_node(t(), String.t()) :: thought_node() | nil
  def get_node(%__MODULE__{nodes: nodes}, node_id) do
    Map.get(nodes, node_id)
  end

  @doc """
  Gets all children of a node.
  """
  @spec get_children(t(), String.t()) :: [thought_node()]
  def get_children(%__MODULE__{nodes: nodes} = machine, node_id) do
    case get_node(machine, node_id) do
      nil -> []
      node -> Enum.map(node.children, &Map.get(nodes, &1)) |> Enum.reject(&is_nil/1)
    end
  end

  @doc """
  Gets the path from root to a given node.
  """
  @spec get_path_to_node(t(), String.t()) :: [thought_node()]
  def get_path_to_node(%__MODULE__{} = machine, node_id) do
    build_path(machine, node_id, [])
  end

  defp build_path(_machine, nil, acc), do: acc

  defp build_path(machine, node_id, acc) do
    case get_node(machine, node_id) do
      nil ->
        acc

      node ->
        build_path(machine, node.parent_id, [node | acc])
    end
  end

  @doc """
  Finds the best leaf node by score.
  """
  @spec find_best_leaf(t()) :: thought_node() | nil
  def find_best_leaf(%__MODULE__{nodes: nodes}) do
    nodes
    |> Map.values()
    |> Enum.filter(&scored_leaf?/1)
    |> Enum.max_by(& &1.score, fn -> nil end)
  end

  defp scored_leaf?(%{children: [], score: score}) when not is_nil(score), do: true
  defp scored_leaf?(_), do: false

  @doc """
  Finds all leaf nodes.
  """
  @spec find_leaves(t()) :: [thought_node()]
  def find_leaves(%__MODULE__{nodes: nodes}) do
    nodes
    |> Map.values()
    |> Enum.filter(&(is_list(&1.children) and &1.children == []))
  end

  # Private helpers

  defp with_transition(machine, new_status, fun) do
    case Fsmx.transition(machine, new_status, state_field: :status) do
      {:ok, machine} -> fun.(machine)
      {:error, _} -> {machine, []}
    end
  end

  defp handle_thoughts_generated(machine, thoughts) when is_list(thoughts) do
    # Store pending thoughts and transition to evaluating
    with_transition(machine, "evaluating", fn machine ->
      machine = Map.put(machine, :pending_thoughts, thoughts)
      call_id = generate_call_id()
      machine = Map.put(machine, :current_call_id, call_id)

      {machine, [{:evaluate_thoughts, call_id, thoughts}]}
    end)
  end

  defp handle_thoughts_evaluated(machine, scores, env) when is_map(scores) do
    current_node = get_node(machine, machine.current_node_id)
    current_depth = current_node.depth

    # Create child nodes for each thought with its score
    {machine, child_ids} =
      Enum.reduce(machine.pending_thoughts, {machine, []}, fn thought, {m, ids} ->
        node_id = generate_node_id()
        score = Map.get(scores, thought, 0.0)

        new_node = %{
          id: node_id,
          parent_id: machine.current_node_id,
          content: thought,
          score: score,
          children: [],
          depth: current_depth + 1
        }

        m = put_in(m.nodes[node_id], new_node)
        {m, [node_id | ids]}
      end)

    child_ids = Enum.reverse(child_ids)

    # Update parent's children list
    machine =
      update_in(machine.nodes[machine.current_node_id].children, fn _ -> child_ids end)

    # Clear pending
    machine =
      machine
      |> Map.put(:pending_thoughts, [])
      |> Map.put(:pending_scores, scores)

    # Check if any solution is complete (score = 1.0)
    complete_solution =
      Enum.find(child_ids, fn id ->
        node = get_node(machine, id)
        node && node.score == 1.0
      end)

    cond do
      complete_solution != nil ->
        # Found a complete solution
        complete_with_solution(machine, complete_solution)

      current_depth + 1 >= machine.max_depth ->
        # Hit max depth - find best solution so far
        complete_with_best_leaf(machine)

      true ->
        # Continue expanding
        expand_next_node(machine, child_ids, env)
    end
  end

  defp handle_llm_result(machine, {:error, reason}, _env) do
    duration_ms = calculate_duration(machine)

    emit_telemetry(:complete, %{duration: duration_ms}, %{
      termination_reason: :error,
      error: reason,
      usage: machine.usage
    })

    with_transition(machine, "error", fn machine ->
      machine =
        machine
        |> Map.put(:termination_reason, :error)
        |> Map.put(:result, "Error: #{inspect(reason)}")

      {machine, []}
    end)
  end

  defp handle_llm_result(%__MODULE__{status: "generating"} = machine, {:ok, result}, _env) do
    # Accumulate usage
    machine = accumulate_usage(machine, result)

    # Parse thoughts from LLM response
    response_text = result.text || machine.streaming_text || ""
    thoughts = parse_thoughts(response_text)

    # Reset streaming text
    machine = Map.put(machine, :streaming_text, "")

    handle_thoughts_generated(machine, thoughts)
  end

  defp handle_llm_result(%__MODULE__{status: "evaluating"} = machine, {:ok, result}, env) do
    # Accumulate usage
    machine = accumulate_usage(machine, result)

    # Parse scores from LLM response
    response_text = result.text || machine.streaming_text || ""
    scores = parse_scores(response_text, machine.pending_thoughts)

    # Reset streaming text
    machine = Map.put(machine, :streaming_text, "")

    handle_thoughts_evaluated(machine, scores, env)
  end

  defp complete_with_solution(machine, solution_node_id) do
    path = get_path_to_node(machine, solution_node_id)
    solution_node = get_node(machine, solution_node_id)
    duration_ms = calculate_duration(machine)

    emit_telemetry(:complete, %{duration: duration_ms}, %{
      termination_reason: :success,
      path_length: length(path),
      node_count: map_size(machine.nodes),
      usage: machine.usage
    })

    with_transition(machine, "completed", fn machine ->
      machine =
        machine
        |> Map.put(:termination_reason, :success)
        |> Map.put(:solution_path, Enum.map(path, & &1.id))
        |> Map.put(:result, solution_node.content)

      {machine, []}
    end)
  end

  defp complete_with_best_leaf(machine) do
    best_leaf = find_best_leaf(machine)
    duration_ms = calculate_duration(machine)

    if best_leaf do
      path = get_path_to_node(machine, best_leaf.id)

      emit_telemetry(:complete, %{duration: duration_ms}, %{
        termination_reason: :max_depth,
        path_length: length(path),
        node_count: map_size(machine.nodes),
        best_score: best_leaf.score,
        usage: machine.usage
      })

      with_transition(machine, "completed", fn machine ->
        machine =
          machine
          |> Map.put(:termination_reason, :max_depth)
          |> Map.put(:solution_path, Enum.map(path, & &1.id))
          |> Map.put(:result, best_leaf.content)

        {machine, []}
      end)
    else
      emit_telemetry(:complete, %{duration: duration_ms}, %{
        termination_reason: :error,
        error: :no_solution_found,
        usage: machine.usage
      })

      with_transition(machine, "error", fn machine ->
        machine =
          machine
          |> Map.put(:termination_reason, :error)
          |> Map.put(:result, "No solution found within max depth")

        {machine, []}
      end)
    end
  end

  defp expand_next_node(machine, new_child_ids, env) do
    # Add new children to frontier based on traversal strategy
    updated_frontier = update_frontier(machine, new_child_ids)

    # Select next node to expand
    case select_next_node(machine, updated_frontier) do
      nil ->
        # No more nodes to expand - find best solution
        complete_with_best_leaf(machine)

      {next_node_id, remaining_frontier} ->
        start_generating_for_node(machine, next_node_id, remaining_frontier, env)
    end
  end

  defp start_generating_for_node(machine, node_id, remaining_frontier, env) do
    # Transition expanding -> generating atomically
    with {:ok, machine} <- Fsmx.transition(machine, "expanding", state_field: :status),
         machine = Map.put(machine, :frontier, remaining_frontier),
         {:ok, machine} <- Fsmx.transition(machine, "generating", state_field: :status) do
      call_id = generate_call_id()

      machine =
        machine
        |> Map.put(:current_node_id, node_id)
        |> Map.put(:current_call_id, call_id)
        |> Map.put(:streaming_text, "")

      context = build_generation_context(machine, node_id, env)

      {machine, [{:generate_thoughts, call_id, context, machine.branching_factor}]}
    else
      {:error, _} -> {machine, []}
    end
  end

  defp update_frontier(machine, new_child_ids) do
    case machine.traversal_strategy do
      :bfs ->
        # Add to end (queue behavior)
        machine.frontier ++ new_child_ids

      :dfs ->
        # Add to front (stack behavior)
        new_child_ids ++ machine.frontier

      :best_first ->
        # Merge and sort by score (descending)
        all_ids = machine.frontier ++ new_child_ids

        all_ids
        |> Enum.map(&{&1, get_node(machine, &1)})
        |> Enum.reject(fn {_id, node} -> is_nil(node) end)
        |> Enum.sort_by(fn {_id, node} -> -(node.score || 0) end)
        |> Enum.map(fn {id, _node} -> id end)
    end
  end

  defp select_next_node(_machine, []), do: nil

  defp select_next_node(machine, [first | rest]) do
    # Check if node is at max depth
    node = get_node(machine, first)

    if node && node.depth < machine.max_depth do
      {first, rest}
    else
      select_next_node(machine, rest)
    end
  end

  defp build_generation_context(machine, node_id, env) do
    path = get_path_to_node(machine, node_id)
    system_prompt = Map.get(env, :generation_prompt, default_generation_prompt())

    # Build context showing the path so far
    path_text =
      path
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {node, idx} ->
        if idx == 0 do
          "Problem: #{node.content}"
        else
          "Step #{idx}: #{node.content}"
        end
      end)

    user_content =
      if length(path) == 1 do
        "Generate #{machine.branching_factor} different approaches to solve this problem:\n\n#{path_text}"
      else
        "Given the reasoning so far, generate #{machine.branching_factor} different next steps:\n\n#{path_text}"
      end

    [
      %{role: :system, content: system_prompt},
      %{role: :user, content: user_content}
    ]
  end

  @doc """
  Parses numbered thoughts from LLM response text.
  """
  @spec parse_thoughts(String.t()) :: [String.t()]
  def parse_thoughts(text) when is_binary(text) do
    # Match patterns like "1. thought" or "1) thought" or "1: thought"
    pattern = ~r/(?:^|\n)\s*(\d+)[.:\)]\s*(.+?)(?=(?:\n\s*\d+[.:\)]|\z))/s

    Regex.scan(pattern, text, capture: :all_but_first)
    |> Enum.map(fn [_num, content] -> String.trim(content) end)
    |> Enum.reject(&(&1 == ""))
  end

  def parse_thoughts(_), do: []

  @doc """
  Parses evaluation scores from LLM response text.
  """
  @spec parse_scores(String.t(), [String.t()]) :: %{String.t() => float()}
  def parse_scores(text, thoughts) when is_binary(text) and is_list(thoughts) do
    # Match patterns like "1: 0.8 - explanation" or "1. 0.8"
    pattern = ~r/(?:^|\n)\s*(\d+)[.:\)]\s*([\d.]+)/

    score_matches =
      Regex.scan(pattern, text, capture: :all_but_first)
      |> Map.new(fn [num, score] ->
        {String.to_integer(num), parse_float(score)}
      end)

    # Map scores to thoughts by index
    thoughts
    |> Enum.with_index(1)
    |> Map.new(fn {thought, idx} ->
      score = Map.get(score_matches, idx, 0.5)
      {thought, min(max(score, 0.0), 1.0)}
    end)
  end

  def parse_scores(_, thoughts) when is_list(thoughts) do
    # Default all to 0.5 if parsing fails
    thoughts |> Map.new(&{&1, 0.5})
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error -> 0.5
    end
  end

  defp accumulate_usage(machine, result) do
    case Map.get(result, :usage) do
      nil ->
        machine

      new_usage when is_map(new_usage) ->
        current = machine.usage

        merged =
          Map.merge(current, new_usage, fn _k, v1, v2 ->
            (v1 || 0) + (v2 || 0)
          end)

        %{machine | usage: merged}
    end
  end

  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(@telemetry_prefix ++ [event], measurements, metadata)
  end

  defp calculate_duration(%{started_at: nil}), do: 0

  defp calculate_duration(%{started_at: started_at}) do
    System.monotonic_time(:millisecond) - started_at
  end
end
