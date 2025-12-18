defmodule Jido.AI.Runner.TreeOfThoughts.ThoughtEvaluator do
  @moduledoc """
  Thought evaluation strategies for Tree-of-Thoughts.

  Evaluates the quality and promise of thoughts to guide search:
  - **Value**: LLM scores thought viability (0=impossible, 0.5=maybe, 1=sure)
  - **Vote**: Multiple evaluations with majority voting
  - **Heuristic**: Domain-specific quality metrics
  - **Hybrid**: Combine multiple evaluation strategies

  ## Evaluation Strategies

  ### Value Evaluation
  Single LLM call returns scalar value 0.0-1.0 indicating thought quality.
  Fast, lower cost, but single opinion.

  ### Vote Evaluation
  Multiple LLM evaluations (typically 3-5) vote on thought quality.
  More robust, catches errors, but higher cost.

  ### Heuristic Evaluation
  Domain-specific rules and metrics (e.g., code syntax, math validity).
  Fast, deterministic, but requires domain knowledge.

  ### Hybrid Evaluation
  Combines multiple strategies for best accuracy/cost tradeoff.

  ## Examples

      # Value evaluation
      {:ok, score} = ThoughtEvaluator.evaluate(
        thought: "Try approach X",
        problem: "Solve Y",
        strategy: :value
      )

      # Vote evaluation (more robust)
      {:ok, score} = ThoughtEvaluator.evaluate(
        thought: "Complex step",
        problem: "Hard problem",
        strategy: :vote,
        num_votes: 5
      )

      # Heuristic (domain-specific)
      {:ok, score} = ThoughtEvaluator.evaluate(
        thought: "def foo(x): return x*2",
        problem: "Write doubling function",
        strategy: :heuristic,
        heuristic_fn: &code_validity_score/1
      )
  """

  require Logger

  @type evaluation_opts :: [
          thought: String.t(),
          problem: String.t(),
          state: map(),
          strategy: :value | :vote | :heuristic | :hybrid,
          num_votes: pos_integer(),
          heuristic_fn: function() | nil,
          evaluation_fn: function() | nil,
          context: map() | nil,
          model: String.t() | nil
        ]

  @doc """
  Evaluates a thought's quality and promise.

  ## Parameters

  - `opts` - Evaluation options:
    - `:thought` - The thought to evaluate (required)
    - `:problem` - The problem context (required)
    - `:state` - Current state (default: %{})
    - `:strategy` - Evaluation strategy (default: :value)
    - `:num_votes` - Number of votes for vote strategy (default: 3)
    - `:heuristic_fn` - Custom heuristic function
    - `:evaluation_fn` - Custom evaluation function (for testing)
    - `:context` - Context for LLM calls (optional)
    - `:model` - Model name for LLM (optional)

  ## Returns

  - `{:ok, score}` - Score from 0.0 to 1.0
  - `{:error, reason}` - Evaluation failed

  ## Examples

      {:ok, score} = ThoughtEvaluator.evaluate(
        thought: "Break problem into sub-problems",
        problem: "Solve complex task",
        strategy: :value
      )
      # => {:ok, 0.75}
  """
  @spec evaluate(evaluation_opts()) :: {:ok, float()} | {:error, term()}
  def evaluate(opts) do
    thought = Keyword.fetch!(opts, :thought)
    problem = Keyword.fetch!(opts, :problem)
    state = Keyword.get(opts, :state, %{})
    strategy = Keyword.get(opts, :strategy, :value)
    num_votes = Keyword.get(opts, :num_votes, 3)
    heuristic_fn = Keyword.get(opts, :heuristic_fn)
    evaluation_fn = Keyword.get(opts, :evaluation_fn)
    context = Keyword.get(opts, :context)
    model = Keyword.get(opts, :model)

    Logger.debug("Evaluating thought with strategy: #{strategy}")

    # Use custom evaluation function if provided (for testing)
    if evaluation_fn do
      {:ok, evaluation_fn.(opts)}
    else
      eval_opts = [
        thought: thought,
        problem: problem,
        state: state,
        num_votes: num_votes,
        heuristic_fn: heuristic_fn,
        context: context,
        model: model
      ]

      case strategy do
        :value -> evaluate_value(eval_opts)
        :vote -> evaluate_vote(eval_opts)
        :heuristic -> evaluate_heuristic(eval_opts)
        :hybrid -> evaluate_hybrid(eval_opts)
      end
    end
  end

  @doc """
  Evaluates multiple thoughts in batch.

  More efficient than individual evaluation when using LLM-based strategies.

  ## Parameters

  - `thoughts` - List of thoughts to evaluate
  - `opts` - Same as evaluate/1

  ## Returns

  - `{:ok, scores}` - List of scores matching thoughts order
  - `{:error, reason}` - Evaluation failed
  """
  @spec evaluate_batch(list(String.t()), evaluation_opts()) ::
          {:ok, list(float())} | {:error, term()}
  def evaluate_batch(thoughts, opts) do
    # For now, evaluate individually
    # In production, could batch LLM calls for efficiency
    results =
      Enum.map(thoughts, fn thought ->
        case evaluate(Keyword.put(opts, :thought, thought)) do
          {:ok, score} ->
            score

          {:error, _} ->
            0.5
            # Default to neutral on error
        end
      end)

    {:ok, results}
  end

  # Private functions

  defp evaluate_value(opts) do
    # Value evaluation: Single LLM call for scalar score
    thought = Keyword.fetch!(opts, :thought)
    problem = Keyword.fetch!(opts, :problem)
    state = Keyword.fetch!(opts, :state)
    context = Keyword.get(opts, :context)
    model = Keyword.get(opts, :model)

    prompt = build_value_prompt(thought, problem, state)
    call_llm_for_value(prompt, model, context)
  end

  defp evaluate_vote(opts) do
    # Vote evaluation: Multiple independent evaluations
    # More robust against single evaluation errors
    thought = Keyword.fetch!(opts, :thought)
    problem = Keyword.fetch!(opts, :problem)
    state = Keyword.fetch!(opts, :state)
    num_votes = Keyword.fetch!(opts, :num_votes)
    context = Keyword.get(opts, :context)
    model = Keyword.get(opts, :model)

    prompt = build_value_prompt(thought, problem, state)

    # Perform multiple independent evaluations
    votes =
      Enum.map(1..num_votes, fn _i ->
        case call_llm_for_value(prompt, model, context) do
          {:ok, score} -> score
          {:error, _} -> 0.5
        end
      end)

    # Aggregate votes (mean)
    avg_score = Enum.sum(votes) / num_votes
    {:ok, avg_score}
  end

  defp evaluate_heuristic(opts) do
    # Heuristic evaluation: Domain-specific rules
    thought = Keyword.fetch!(opts, :thought)
    problem = Keyword.fetch!(opts, :problem)
    state = Keyword.fetch!(opts, :state)
    heuristic_fn = Keyword.get(opts, :heuristic_fn)

    score =
      if heuristic_fn do
        heuristic_fn.(%{thought: thought, problem: problem, state: state})
      else
        # Default heuristics
        default_heuristic_score(thought, problem, state)
      end

    {:ok, score}
  end

  defp evaluate_hybrid(opts) do
    # Hybrid: Combine value, vote, and heuristic

    # Get value score (fast)
    {:ok, value_score} = evaluate_value(opts)

    # Get heuristic score (fast, deterministic)
    {:ok, heuristic_score} = evaluate_heuristic(opts)

    # Combine with weights
    # If heuristic is very confident (close to 0 or 1), trust it more
    heuristic_confidence = abs(heuristic_score - 0.5) * 2

    # Weighted combination
    combined =
      if heuristic_confidence > 0.7 do
        # Trust heuristic more
        heuristic_score * 0.7 + value_score * 0.3
      else
        # Balance heuristic and value
        heuristic_score * 0.4 + value_score * 0.6
      end

    {:ok, combined}
  end

  defp build_value_prompt(thought, problem, state) do
    """
    Problem: #{problem}

    Current state: #{inspect(state, pretty: true)}

    Thought to evaluate: #{thought}

    Evaluate the quality and promise of this thought on a scale from 0.0 to 1.0:
    - 0.0: This thought is clearly wrong or will lead to a dead end
    - 0.5: This thought is uncertain, may or may not be helpful
    - 1.0: This thought is very promising and likely to lead to a solution

    Return ONLY a single number between 0.0 and 1.0.
    """
  end

  defp call_llm_for_value(prompt, model_str, _context) do
    system_message = """
    You are an expert reasoning evaluator.
    Your task is to evaluate the quality and promise of reasoning steps.

    Return ONLY a single floating point number between 0.0 and 1.0.
    Do not include any explanation, just the number.
    """

    # Build model (default to openai:gpt-4 if not specified)
    model = build_model(model_str || "openai:gpt-4")

    # Build ReqLLM model tuple with options
    reqllm_model =
      {model.provider, model.model,
       [
         temperature: 0.3,
         max_tokens: 10
       ]
       |> maybe_add_api_key(model)}

    # Build messages using ReqLLM.Context
    messages = [
      ReqLLM.Context.system(system_message),
      ReqLLM.Context.user(prompt)
    ]

    try do
      case ReqLLM.generate_text(reqllm_model, messages) do
        {:ok, response} ->
          content = String.trim(ReqLLM.Response.text(response) || "")

          # Parse the score
          case Float.parse(content) do
            {score, _} when score >= 0.0 and score <= 1.0 ->
              {:ok, score}

            _ ->
              {:error, :invalid_score}
          end

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        {:error, {:llm_error, error}}
    end
  end

  # Build a ReqLLM.Model from a model string
  defp build_model(model_str) when is_binary(model_str) do
    case String.split(model_str, ":", parts: 2) do
      [provider_str, model_name] ->
        provider = String.to_atom(provider_str)
        # Create ReqLLM.Model directly
        {:ok, model} = ReqLLM.Model.from("#{provider}:#{model_name}")
        model

      [model_name] ->
        # Create ReqLLM.Model directly with default provider
        {:ok, model} = ReqLLM.Model.from("openai:#{model_name}")
        model
    end
  end

  defp build_model(_), do: build_model("openai:gpt-4")

  # Add API key to options if present in model
  defp maybe_add_api_key(opts, %Jido.AI.Model{api_key: api_key}) when is_binary(api_key) do
    Keyword.put(opts, :api_key, api_key)
  end

  defp maybe_add_api_key(opts, _model), do: opts

  @doc """
  Simulates value evaluation for testing purposes.

  This function generates fake evaluation scores without calling an LLM.
  Use this via the `evaluation_fn` parameter in tests.

  ## Parameters

  - `thought` - The thought to evaluate
  - `problem` - The problem context
  - `state` - Current state

  ## Returns

  Simulated score from 0.0 to 1.0
  """
  @spec simulate_value_evaluation(String.t(), String.t(), map()) :: float()
  def simulate_value_evaluation(thought, problem, _state) do
    # Simulate LLM value evaluation
    # In production, this would be actual LLM call

    # Simple heuristic for simulation
    thought_length = String.length(thought)
    _problem_length = String.length(problem)

    # Longer, more detailed thoughts score higher
    length_score = min(1.0, thought_length / 100.0)

    # Thoughts mentioning key problem terms score higher
    problem_words = problem |> String.downcase() |> String.split()

    relevance_score =
      problem_words
      |> Enum.count(fn word ->
        String.contains?(String.downcase(thought), word)
      end)
      |> Kernel./(max(1, length(problem_words)))

    # Combine factors
    base_score = length_score * 0.3 + relevance_score * 0.7

    # Add some randomness to simulate LLM variability
    noise = (:rand.uniform() - 0.5) * 0.2
    clamped_score = max(0.0, min(1.0, base_score + noise))

    clamped_score
  end

  @doc """
  Default heuristic scoring for testing purposes.

  This function provides basic heuristic scoring without domain-specific knowledge.
  Use this via the `heuristic_fn` parameter in tests.

  ## Parameters

  - `thought` - The thought to evaluate
  - `problem` - The problem context
  - `state` - Current state

  ## Returns

  Heuristic score from 0.0 to 1.0
  """
  @spec default_heuristic_score(String.t(), String.t(), map()) :: float()
  def default_heuristic_score(thought, _problem, _state) do
    # Default heuristics when no custom function provided

    score = 0.5

    # Penalize very short thoughts (likely incomplete)
    score =
      if String.length(thought) < 10 do
        score * 0.5
      else
        score
      end

    # Reward thoughts with specific actions or steps
    action_words = ["calculate", "check", "verify", "try", "apply", "use", "consider"]

    has_action =
      Enum.any?(action_words, fn word ->
        String.contains?(String.downcase(thought), word)
      end)

    score =
      if has_action do
        score + 0.2
      else
        score
      end

    # Reward thoughts with conditional logic
    has_conditional = String.contains?(thought, ["if", "when", "unless", "in case"])

    score =
      if has_conditional do
        score + 0.1
      else
        score
      end

    max(0.0, min(1.0, score))
  end
end
