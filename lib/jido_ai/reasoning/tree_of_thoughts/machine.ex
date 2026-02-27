defmodule Jido.AI.Reasoning.TreeOfThoughts.Machine do
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

  # Fsmx macro expansion emits a spurious `warn_matching` on this module.
  @dialyzer :no_match

  # Telemetry event names
  @telemetry_prefix [:jido, :ai, :tot]

  alias Jido.AI.Reasoning.TreeOfThoughts.Result

  @typedoc "Internal machine status (string) - required by Fsmx library"
  @type internal_status :: String.t()

  @typedoc "External status (atom) - used in strategy state after to_map/1 conversion"
  @type external_status :: :idle | :generating | :evaluating | :expanding | :completed | :error

  @type termination_reason ::
          :success
          | :threshold
          | :max_depth
          | :max_nodes
          | :max_duration
          | :converged
          | :error
          | nil
  @type traversal_strategy :: :bfs | :dfs | :best_first

  @type thought_entry :: %{
          id: String.t(),
          content: String.t()
        }

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
          pending_thoughts: [thought_entry()],
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
          frontier: [String.t()],
          top_k: pos_integer(),
          min_depth: non_neg_integer(),
          max_nodes: pos_integer(),
          max_duration_ms: pos_integer() | nil,
          beam_width: pos_integer() | nil,
          early_success_threshold: float(),
          convergence_window: pos_integer(),
          min_score_improvement: float(),
          max_parse_retries: non_neg_integer(),
          parser_mode: atom() | nil,
          parse_retries: %{generation: non_neg_integer(), evaluation: non_neg_integer()},
          parser_errors: [atom()],
          recent_best_scores: [float()]
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
            frontier: [],
            top_k: 3,
            min_depth: 2,
            max_nodes: 100,
            max_duration_ms: nil,
            beam_width: nil,
            early_success_threshold: 1.0,
            convergence_window: 2,
            min_score_improvement: 0.02,
            max_parse_retries: 1,
            parser_mode: nil,
            parse_retries: %{generation: 0, evaluation: 0},
            parser_errors: [],
            recent_best_scores: []

  @type msg ::
          {:start, prompt :: String.t(), call_id :: String.t()}
          | {:thoughts_generated, call_id :: String.t(), thoughts :: [String.t()]}
          | {:thoughts_evaluated, call_id :: String.t(), scores :: %{String.t() => float()}}
          | {:llm_result, call_id :: String.t(), result :: term()}
          | {:llm_partial, call_id :: String.t(), delta :: String.t(), chunk_type :: atom()}

  @type directive ::
          {:generate_thoughts, id :: String.t(), context :: list(), count :: pos_integer()}
          | {:evaluate_thoughts, id :: String.t(), thoughts :: [thought_entry()]}
          | {:call_llm_stream, id :: String.t(), context :: list()}
          | {:request_error, id :: String.t(), atom(), String.t()}

  @doc """
  Creates a new machine in the idle state.

  ## Options

  - `:branching_factor` - Number of thoughts to generate at each node (default: 3)
  - `:max_depth` - Maximum depth of the tree (default: 3)
  - `:traversal_strategy` - `:bfs`, `:dfs`, or `:best_first` (default: `:best_first`)
  - `:top_k` - Number of ranked candidates in final result (default: 3)
  - `:min_depth` - Minimum depth before early success completion (default: 2)
  - `:max_nodes` - Hard cap on explored nodes (default: 100)
  - `:max_duration_ms` - Optional wall-time cap in milliseconds
  - `:beam_width` - Optional frontier cap for best-first expansion
  - `:early_success_threshold` - Score threshold for early completion (default: 1.0)
  - `:convergence_window` - Number of recent best scores for convergence check (default: 2)
  - `:min_score_improvement` - Minimum best-score improvement required across convergence window (default: 0.02)
  - `:max_parse_retries` - Number of parser repair retries per phase (default: 1)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      branching_factor: Keyword.get(opts, :branching_factor, 3),
      max_depth: Keyword.get(opts, :max_depth, 3),
      traversal_strategy: Keyword.get(opts, :traversal_strategy, :best_first),
      top_k: Keyword.get(opts, :top_k, 3),
      min_depth: Keyword.get(opts, :min_depth, 2),
      max_nodes: Keyword.get(opts, :max_nodes, 100),
      max_duration_ms: Keyword.get(opts, :max_duration_ms),
      beam_width: Keyword.get(opts, :beam_width),
      early_success_threshold: Keyword.get(opts, :early_success_threshold, 1.0),
      convergence_window: Keyword.get(opts, :convergence_window, 2),
      min_score_improvement: Keyword.get(opts, :min_score_improvement, 0.02),
      max_parse_retries: Keyword.get(opts, :max_parse_retries, 1)
    }
  end

  # Provide the deprecated arity expected by Fsmx runtime checks so transitions
  # can use this explicit callback path without relying on generated fallback.
  @spec before_transition(t(), internal_status(), internal_status()) :: {:ok, t()}
  def before_transition(struct, _from, _to), do: {:ok, struct}

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
        |> Map.put(:parser_mode, nil)
        |> Map.put(:parse_retries, %{generation: 0, evaluation: 0})
        |> Map.put(:parser_errors, [])
        |> Map.put(:recent_best_scores, [])

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
    frontier: [],
    top_k: 3,
    min_depth: 2,
    max_nodes: 100,
    max_duration_ms: nil,
    beam_width: nil,
    early_success_threshold: 1.0,
    convergence_window: 2,
    min_score_improvement: 0.02,
    max_parse_retries: 1,
    parser_mode: nil,
    parse_retries: %{generation: 0, evaluation: 0},
    parser_errors: [],
    recent_best_scores: []
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
    :frontier,
    :top_k,
    :min_depth,
    :max_nodes,
    :max_duration_ms,
    :beam_width,
    :early_success_threshold,
    :convergence_window,
    :min_score_improvement,
    :max_parse_retries,
    :parser_mode,
    :parse_retries,
    :parser_errors,
    :recent_best_scores
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

    Return strict JSON with this shape:
    {"thoughts":[{"id":"t1","content":"..."},{"id":"t2","content":"..."}]}

    Rules:
    - each thought must be materially different
    - keep each thought concise
    - return valid JSON only (no markdown wrappers)
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

    Return strict JSON with this shape:
    {"scores":{"t1":0.82,"t2":0.61}}

    Rules:
    - keys must match provided thought IDs
    - scores must be numeric in [0.0, 1.0]
    - return valid JSON only (no markdown wrappers)
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
    thought_entries = normalize_thought_entries(thoughts)

    if thought_entries == [] do
      fail_parse(machine, :generation, :empty_generation_parse)
    else
      # Store pending thoughts and transition to evaluating
      with_transition(machine, "evaluating", fn machine ->
        machine = Map.put(machine, :pending_thoughts, thought_entries)
        call_id = generate_call_id()
        machine = Map.put(machine, :current_call_id, call_id)

        {machine, [{:evaluate_thoughts, call_id, thought_entries}]}
      end)
    end
  end

  defp handle_thoughts_evaluated(machine, scores, env) when is_map(scores) do
    thought_entries = normalize_thought_entries(machine.pending_thoughts)

    if thought_entries == [] do
      fail_parse(machine, :evaluation, :missing_pending_thoughts)
    else
      current_node = get_node(machine, machine.current_node_id)
      current_depth = current_node.depth

      # Create child nodes for each thought with its score.
      {machine, child_ids} =
        Enum.reduce(thought_entries, {machine, []}, fn thought_entry, {m, ids} ->
          node_id = generate_node_id()
          score = score_for_entry(scores, thought_entry)

          new_node = %{
            id: node_id,
            parent_id: machine.current_node_id,
            content: thought_entry.content,
            score: score,
            children: [],
            depth: current_depth + 1
          }

          m = put_in(m.nodes[node_id], new_node)
          {m, [node_id | ids]}
        end)

      child_ids = Enum.reverse(child_ids)

      machine =
        machine
        |> update_in([Access.key(:nodes), Access.key(machine.current_node_id), Access.key(:children)], fn _ ->
          child_ids
        end)
        |> Map.put(:pending_thoughts, [])
        |> Map.put(:pending_scores, scores)
        |> update_recent_best_scores()

      cond do
        budget_reason = budget_termination_reason(machine) ->
          complete_with_best_leaf(machine, budget_reason)

        complete_solution = find_threshold_solution(machine, child_ids) ->
          complete_with_solution(machine, complete_solution, :threshold)

        converged?(machine) ->
          complete_with_best_leaf(machine, :converged)

        current_depth + 1 >= machine.max_depth ->
          complete_with_best_leaf(machine, :max_depth)

        true ->
          expand_next_node(machine, child_ids, env)
      end
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
      machine = Map.put(machine, :termination_reason, :error)
      machine = Map.put(machine, :result, error_result(machine, reason))

      {machine, []}
    end)
  end

  defp handle_llm_result(machine, {:error, reason, _effects}, env) do
    handle_llm_result(machine, {:error, reason}, env)
  end

  defp handle_llm_result(%__MODULE__{status: "generating"} = machine, {:ok, result, _effects}, env) do
    handle_llm_result(machine, {:ok, result}, env)
  end

  defp handle_llm_result(%__MODULE__{status: "evaluating"} = machine, {:ok, result, _effects}, env) do
    handle_llm_result(machine, {:ok, result}, env)
  end

  defp handle_llm_result(%__MODULE__{status: "generating"} = machine, {:ok, result}, _env) do
    # Accumulate usage
    machine = accumulate_usage(machine, result)

    # Parse thoughts from LLM response
    response_text = result.text || machine.streaming_text || ""
    {thoughts, parse_mode} = parse_thoughts(response_text)

    # Reset streaming text
    machine = Map.put(machine, :streaming_text, "")
    machine = Map.put(machine, :parser_mode, parse_mode)

    if thoughts == [] do
      maybe_retry_parse(machine, :generation, response_text, fn retry_machine ->
        fail_parse(retry_machine, :generation, :thoughts_parse_failed)
      end)
    else
      handle_thoughts_generated(machine, thoughts)
    end
  end

  defp handle_llm_result(%__MODULE__{status: "evaluating"} = machine, {:ok, result}, env) do
    # Accumulate usage
    machine = accumulate_usage(machine, result)

    # Parse scores from LLM response
    response_text = result.text || machine.streaming_text || ""
    {scores, parse_mode} = parse_scores(response_text, machine.pending_thoughts)

    # Reset streaming text
    machine = Map.put(machine, :streaming_text, "")
    machine = Map.put(machine, :parser_mode, parse_mode)

    if map_size(scores) == 0 do
      maybe_retry_parse(machine, :evaluation, response_text, fn retry_machine ->
        fail_parse(retry_machine, :evaluation, :scores_parse_failed)
      end)
    else
      handle_thoughts_evaluated(machine, scores, env)
    end
  end

  defp complete_with_solution(machine, solution_node_id, reason) do
    path = get_path_to_node(machine, solution_node_id)
    solution_node = get_node(machine, solution_node_id)
    duration_ms = calculate_duration(machine)

    emit_telemetry(:complete, %{duration: duration_ms}, %{
      termination_reason: reason,
      path_length: length(path),
      node_count: map_size(machine.nodes),
      usage: machine.usage
    })

    with_transition(machine, "completed", fn machine ->
      machine =
        machine
        |> Map.put(:termination_reason, reason)
        |> Map.put(:solution_path, Enum.map(path, & &1.id))

      machine = Map.put(machine, :result, success_result(machine, solution_node.id))

      {machine, []}
    end)
  end

  defp complete_with_best_leaf(machine, reason) do
    best_leaf = find_best_leaf(machine)
    duration_ms = calculate_duration(machine)

    if best_leaf do
      path = get_path_to_node(machine, best_leaf.id)

      emit_telemetry(:complete, %{duration: duration_ms}, %{
        termination_reason: reason,
        path_length: length(path),
        node_count: map_size(machine.nodes),
        best_score: best_leaf.score,
        usage: machine.usage
      })

      with_transition(machine, "completed", fn machine ->
        machine =
          machine
          |> Map.put(:termination_reason, reason)
          |> Map.put(:solution_path, Enum.map(path, & &1.id))

        machine = Map.put(machine, :result, success_result(machine, best_leaf.id))

        {machine, []}
      end)
    else
      emit_telemetry(:complete, %{duration: duration_ms}, %{
        termination_reason: :error,
        error: :no_solution_found,
        usage: machine.usage
      })

      with_transition(machine, "error", fn machine ->
        machine = machine |> Map.put(:termination_reason, :error)
        machine = Map.put(machine, :result, error_result(machine, :no_solution_found))

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
        complete_with_best_leaf(machine, :max_depth)

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

        frontier =
          all_ids
          |> Enum.map(&{&1, get_node(machine, &1)})
          |> Enum.reject(fn {_id, node} -> is_nil(node) end)
          |> Enum.sort_by(fn {_id, node} -> -(node.score || 0) end)
          |> Enum.map(fn {id, _node} -> id end)

        maybe_trim_beam(frontier, machine.beam_width)
    end
  end

  defp select_next_node(_machine, []), do: nil

  # Frontier only contains expandable nodes (depth < max_depth) by construction.
  defp select_next_node(_machine, [first | rest]), do: {first, rest}

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
  @spec parse_thoughts(String.t()) :: {[String.t()], atom()}
  def parse_thoughts(text) when is_binary(text) do
    case parse_thoughts_json(text) do
      {:ok, thoughts} when thoughts != [] ->
        {thoughts, :json}

      _ ->
        {parse_thoughts_regex(text), :regex}
    end
  end

  def parse_thoughts(_), do: {[], :none}

  @doc """
  Parses evaluation scores from LLM response text.
  """
  @spec parse_scores(String.t(), [thought_entry() | String.t()]) :: {%{String.t() => float()}, atom()}
  def parse_scores(text, thoughts) when is_binary(text) and is_list(thoughts) do
    case parse_scores_json(text, thoughts) do
      {:ok, scores} when map_size(scores) > 0 ->
        {scores, :json}

      _ ->
        {parse_scores_regex(text, thoughts), :regex}
    end
  end

  def parse_scores(_, thoughts) when is_list(thoughts) do
    {default_scores(thoughts), :default}
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error -> 0.5
    end
  end

  defp parse_thoughts_json(text) do
    text
    |> extract_json_payload()
    |> decode_json()
    |> case do
      {:ok, %{"thoughts" => thoughts}} when is_list(thoughts) ->
        parsed =
          thoughts
          |> Enum.map(fn
            %{"content" => content} when is_binary(content) -> String.trim(content)
            %{content: content} when is_binary(content) -> String.trim(content)
            content when is_binary(content) -> String.trim(content)
            _ -> ""
          end)
          |> Enum.reject(&(&1 == ""))

        {:ok, parsed}

      _ ->
        {:error, :invalid_json}
    end
  end

  defp parse_thoughts_regex(text) do
    pattern = ~r/(?:^|\n)\s*(\d+)[.:\)]\s*(.+?)(?=(?:\n\s*\d+[.:\)]|\z))/s

    Regex.scan(pattern, text, capture: :all_but_first)
    |> Enum.map(fn [_num, content] -> String.trim(content) end)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_scores_json(text, thoughts) do
    case extract_json_payload(text) |> decode_json() do
      {:ok, %{"scores" => scores}} when is_map(scores) ->
        {:ok, scores_from_json(scores, thoughts)}

      {:ok, %{scores: scores}} when is_map(scores) ->
        {:ok, scores_from_json(scores, thoughts)}

      _ ->
        {:error, :invalid_json}
    end
  end

  defp parse_scores_regex(text, thoughts) do
    pattern = ~r/(?:^|\n)\s*(\d+)[.:\)]\s*([\d.]+)/

    score_matches =
      Regex.scan(pattern, text, capture: :all_but_first)
      |> Map.new(fn [num, score] ->
        {String.to_integer(num), clamp_score(parse_float(score))}
      end)

    thoughts
    |> normalize_thought_entries()
    |> Enum.with_index(1)
    |> Map.new(fn {entry, idx} ->
      {entry.id, Map.get(score_matches, idx, 0.5)}
    end)
  end

  defp scores_from_json(scores_map, thoughts) do
    thoughts
    |> normalize_thought_entries()
    |> Enum.with_index(1)
    |> Map.new(fn {entry, idx} ->
      score =
        Map.get(scores_map, entry.id) ||
          Map.get(scores_map, to_string(idx)) ||
          Map.get(scores_map, entry.content) ||
          0.5

      {entry.id, clamp_score(score)}
    end)
  end

  defp default_scores(thoughts) do
    thoughts
    |> normalize_thought_entries()
    |> Map.new(&{&1.id, 0.5})
  end

  defp clamp_score(score) when is_number(score), do: min(max(score * 1.0, 0.0), 1.0)
  defp clamp_score(score) when is_binary(score), do: score |> parse_float() |> clamp_score()
  defp clamp_score(_), do: 0.5

  defp extract_json_payload(text) do
    case Regex.run(~r/```(?:json)?\s*(\{.*\})\s*```/s, text) do
      [_, payload] -> payload
      _ -> text
    end
  end

  defp decode_json(payload) do
    case Jason.decode(payload) do
      {:ok, decoded} -> {:ok, decoded}
      _ -> {:error, :json_decode_failed}
    end
  end

  defp normalize_thought_entries(thoughts) do
    thoughts
    |> Enum.with_index(1)
    |> Enum.map(fn
      {%{id: id, content: content}, _idx} when is_binary(id) and is_binary(content) ->
        %{id: id, content: content}

      {%{"id" => id, "content" => content}, _idx} when is_binary(id) and is_binary(content) ->
        %{id: id, content: content}

      {%{content: content}, idx} when is_binary(content) ->
        %{id: "t#{idx}", content: content}

      {%{"content" => content}, idx} when is_binary(content) ->
        %{id: "t#{idx}", content: content}

      {content, idx} when is_binary(content) ->
        %{id: "t#{idx}", content: content}

      {_other, idx} ->
        %{id: "t#{idx}", content: ""}
    end)
    |> Enum.reject(&(&1.content == ""))
  end

  defp score_for_entry(scores, %{id: id, content: content}) do
    score =
      Map.get(scores, id) ||
        Map.get(scores, content) ||
        0.5

    clamp_score(score)
  end

  defp score_for_entry(scores, content) when is_binary(content) do
    score = Map.get(scores, content) || 0.5
    clamp_score(score)
  end

  defp update_recent_best_scores(%__MODULE__{} = machine) do
    best_score =
      case find_best_leaf(machine) do
        %{score: score} when is_number(score) -> score
        _ -> 0.0
      end

    window = max(machine.convergence_window, 1)

    recent =
      (machine.recent_best_scores ++ [best_score])
      |> Enum.take(-window)

    %{machine | recent_best_scores: recent}
  end

  defp budget_termination_reason(%__MODULE__{} = machine) do
    cond do
      max_nodes_exceeded?(machine) -> :max_nodes
      max_duration_exceeded?(machine) -> :max_duration
      true -> nil
    end
  end

  defp max_nodes_exceeded?(%__MODULE__{max_nodes: max_nodes, nodes: nodes}) do
    is_integer(max_nodes) and max_nodes > 0 and map_size(nodes) >= max_nodes
  end

  defp max_duration_exceeded?(%__MODULE__{max_duration_ms: nil}), do: false

  defp max_duration_exceeded?(%__MODULE__{max_duration_ms: ms} = machine) when is_integer(ms) and ms > 0 do
    calculate_duration(machine) >= ms
  end

  defp max_duration_exceeded?(_), do: false

  defp find_threshold_solution(machine, child_ids) do
    threshold = machine.early_success_threshold

    Enum.find(child_ids, fn id ->
      case get_node(machine, id) do
        %{score: score, depth: depth} when is_number(score) and is_integer(depth) ->
          score >= threshold and depth >= machine.min_depth

        _ ->
          false
      end
    end)
  end

  defp converged?(%__MODULE__{
         recent_best_scores: scores,
         convergence_window: window,
         min_score_improvement: min_improvement
       })
       when is_list(scores) and is_integer(window) and window > 1 do
    if length(scores) < window do
      false
    else
      first = hd(scores)
      last = List.last(scores)
      improvement = last - first
      improvement < min_improvement
    end
  end

  defp converged?(_), do: false

  defp maybe_trim_beam(frontier, beam_width) when is_integer(beam_width) and beam_width > 0 do
    Enum.take(frontier, beam_width)
  end

  defp maybe_trim_beam(frontier, _), do: frontier

  defp maybe_retry_parse(%__MODULE__{} = machine, phase, raw_text, on_exhausted)
       when phase in [:generation, :evaluation] and is_function(on_exhausted, 1) do
    retries = get_in(machine.parse_retries, [phase]) || 0

    if retries < machine.max_parse_retries do
      call_id = generate_call_id()

      parse_retries =
        machine.parse_retries
        |> Kernel.||(%{})
        |> Map.put(phase, retries + 1)

      machine =
        machine
        |> Map.put(:parse_retries, parse_retries)
        |> Map.update(:parser_errors, [:"#{phase}_parse_retry"], fn errors ->
          errors ++ [:"#{phase}_parse_retry"]
        end)
        |> Map.put(:current_call_id, call_id)
        |> Map.put(:streaming_text, "")

      context = build_parse_repair_context(machine, phase, raw_text)
      {machine, [{:call_llm_stream, call_id, context}]}
    else
      on_exhausted.(machine)
    end
  end

  defp build_parse_repair_context(machine, :generation, raw_text) do
    system_prompt = "You convert noisy model output into strict JSON."

    user_prompt = """
    Reformat the following text into strict JSON using:
    {"thoughts":[{"id":"t1","content":"..."},{"id":"t2","content":"..."}]}

    Requirements:
    - return valid JSON only
    - include #{machine.branching_factor} thoughts if possible
    - keep content concise and non-empty

    SOURCE:
    #{raw_text}
    """

    [
      %{role: :system, content: system_prompt},
      %{role: :user, content: user_prompt}
    ]
  end

  defp build_parse_repair_context(machine, :evaluation, raw_text) do
    thought_ids =
      machine.pending_thoughts
      |> Enum.map_join(", ", & &1.id)

    system_prompt = "You convert noisy scoring output into strict JSON."

    user_prompt = """
    Reformat the following text into strict JSON using:
    {"scores":{"t1":0.82,"t2":0.61}}

    Requirements:
    - return valid JSON only
    - keys must be thought IDs from: #{thought_ids}
    - each score must be between 0.0 and 1.0

    SOURCE:
    #{raw_text}
    """

    [
      %{role: :system, content: system_prompt},
      %{role: :user, content: user_prompt}
    ]
  end

  defp fail_parse(%__MODULE__{} = machine, phase, reason) do
    machine =
      machine
      |> Map.update(:parser_errors, [reason], fn errors -> errors ++ [reason] end)
      |> Map.put(:termination_reason, :error)

    machine = Map.put(machine, :result, error_result(machine, {:parse_failed, phase, reason}))

    with_transition(machine, "error", fn machine -> {machine, []} end)
  end

  defp success_result(%__MODULE__{} = machine, best_node_id) do
    Result.build(machine,
      top_k: machine.top_k,
      diagnostics: diagnostics(machine, best_node_id)
    )
  end

  defp error_result(%__MODULE__{} = machine, reason) do
    base =
      Result.build(machine,
        top_k: machine.top_k,
        diagnostics: diagnostics(machine, nil)
      )

    base
    |> put_in([:termination, :reason], :error)
    |> put_in([:diagnostics, :error], inspect(reason))
  end

  defp diagnostics(%__MODULE__{} = machine, best_node_id) do
    %{
      parser_mode: machine.parser_mode,
      parse_retries: machine.parse_retries,
      parser_errors: machine.parser_errors,
      tool_rounds: %{},
      convergence: %{
        window: machine.convergence_window,
        min_score_improvement: machine.min_score_improvement,
        recent_best_scores: machine.recent_best_scores
      },
      best_node_id: best_node_id
    }
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
