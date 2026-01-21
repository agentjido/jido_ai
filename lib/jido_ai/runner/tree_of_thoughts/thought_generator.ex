defmodule Jido.AI.Runner.TreeOfThoughts.ThoughtGenerator do
  @moduledoc """
  Thought generation strategies for Tree-of-Thoughts.

  Generates diverse candidate thoughts at each tree node using:
  - **Sampling**: Temperature-based diverse i.i.d. thoughts
  - **Proposal**: Sequential deliberate thought generation
  - **Beam Width**: Configurable k thoughts per node
  - **Adaptive**: Dynamic k based on depth and tree size

  ## Strategies

  ### Sampling Strategy
  Uses high temperature (0.7-1.0) to generate diverse independent thoughts.
  Good for creative exploration and generating varied approaches.

  ### Proposal Strategy
  Uses lower temperature (0.3-0.5) for deliberate, sequential thoughts.
  Each thought builds on previous ones. Good for structured problems.

  ## Examples

      # Sampling strategy (creative)
      {:ok, thoughts} = ThoughtGenerator.generate(
        problem: "Solve 24 with numbers 4, 5, 6, 6",
        parent_state: %{numbers: [4,5,6,6]},
        strategy: :sampling,
        beam_width: 5,
        temperature: 0.8
      )

      # Proposal strategy (structured)
      {:ok, thoughts} = ThoughtGenerator.generate(
        problem: "Write quicksort in Elixir",
        parent_state: %{},
        strategy: :proposal,
        beam_width: 3
      )
  """

  require Logger

  @default_beam_width 5
  @default_temperature 0.7
  @sampling_temperature 0.8
  @proposal_temperature 0.4

  @type generation_opts :: [
          problem: String.t(),
          parent_state: map(),
          strategy: :sampling | :proposal | :adaptive,
          beam_width: pos_integer(),
          temperature: float(),
          depth: non_neg_integer(),
          tree_size: non_neg_integer(),
          thought_fn: function() | nil,
          context: map() | nil,
          model: String.t() | nil
        ]

  @doc """
  Generates candidate thoughts for expansion.

  ## Parameters

  - `opts` - Generation options:
    - `:problem` - The problem being solved (required)
    - `:parent_state` - State at parent node (required)
    - `:strategy` - Generation strategy (:sampling, :proposal, :adaptive)
    - `:beam_width` - Number of thoughts to generate (default: 5)
    - `:temperature` - LLM temperature (default: 0.7)
    - `:depth` - Current depth in tree
    - `:tree_size` - Current tree size
    - `:thought_fn` - Custom thought generation function (for testing)
    - `:context` - Context for LLM calls (optional)
    - `:model` - Model name for LLM (optional)

  ## Returns

  - `{:ok, thoughts}` - List of thought strings
  - `{:error, reason}` - Generation failed

  ## Examples

      {:ok, thoughts} = ThoughtGenerator.generate(
        problem: "What is 15% of 80?",
        parent_state: %{},
        strategy: :sampling,
        beam_width: 5
      )
      # => {:ok, ["Approach 1: Convert to decimal...", "Approach 2: Use fraction...", ...]}
  """
  @spec generate(generation_opts()) :: {:ok, list(String.t())} | {:error, term()}
  def generate(opts) do
    problem = Keyword.fetch!(opts, :problem)
    parent_state = Keyword.fetch!(opts, :parent_state)
    strategy = Keyword.get(opts, :strategy, :sampling)
    beam_width = Keyword.get(opts, :beam_width, @default_beam_width)
    temperature = Keyword.get(opts, :temperature, @default_temperature)
    depth = Keyword.get(opts, :depth, 0)
    tree_size = Keyword.get(opts, :tree_size, 0)
    thought_fn = Keyword.get(opts, :thought_fn)
    context = Keyword.get(opts, :context)
    model = Keyword.get(opts, :model)

    # Determine effective beam width (adaptive if needed)
    effective_beam_width =
      if strategy == :adaptive do
        adaptive_beam_width(beam_width, depth, tree_size)
      else
        beam_width
      end

    # Determine effective temperature
    effective_temperature =
      case strategy do
        :sampling -> Keyword.get(opts, :temperature, @sampling_temperature)
        :proposal -> Keyword.get(opts, :temperature, @proposal_temperature)
        :adaptive -> temperature
      end

    Logger.debug(
      "Generating #{effective_beam_width} thoughts with strategy: #{strategy}, temp: #{effective_temperature}"
    )

    # Use custom thought function if provided (for testing)
    if thought_fn do
      thoughts = thought_fn.(opts)
      {:ok, thoughts}
    else
      generation_opts = [
        problem: problem,
        parent_state: parent_state,
        beam_width: effective_beam_width,
        temperature: effective_temperature,
        context: context,
        model: model
      ]

      case strategy do
        :sampling -> generate_sampling(generation_opts)
        :proposal -> generate_proposal(generation_opts)
        :adaptive -> generate_sampling(generation_opts)
      end
    end
  end

  @doc """
  Calculates adaptive beam width based on depth and tree size.

  Reduces beam width at deeper levels to control exponential growth.

  ## Parameters

  - `base_beam_width` - Base beam width
  - `depth` - Current depth
  - `tree_size` - Current tree size

  ## Returns

  Adjusted beam width
  """
  @spec adaptive_beam_width(pos_integer(), non_neg_integer(), non_neg_integer()) :: pos_integer()
  def adaptive_beam_width(base_beam_width, depth, tree_size) do
    # Reduce beam width as depth increases
    depth_factor = max(1, base_beam_width - div(depth, 2))

    # Reduce if tree is getting too large
    size_factor =
      cond do
        tree_size > 1000 -> max(2, div(base_beam_width, 2))
        tree_size > 500 -> max(3, base_beam_width - 1)
        true -> base_beam_width
      end

    min(depth_factor, size_factor)
  end

  # Private functions

  defp generate_sampling(opts) do
    # Sampling strategy: Generate diverse i.i.d. thoughts in parallel
    # Each thought is independent, exploring different approaches

    problem = Keyword.fetch!(opts, :problem)
    parent_state = Keyword.fetch!(opts, :parent_state)
    beam_width = Keyword.fetch!(opts, :beam_width)
    temperature = Keyword.fetch!(opts, :temperature)
    context = Keyword.get(opts, :context)
    model = Keyword.get(opts, :model)

    prompt = build_sampling_prompt(problem, parent_state, beam_width)
    call_llm(prompt, beam_width, temperature, model, context)
  end

  defp generate_proposal(opts) do
    # Proposal strategy: Generate thoughts sequentially
    # Each thought is aware of previous proposals

    problem = Keyword.fetch!(opts, :problem)
    parent_state = Keyword.fetch!(opts, :parent_state)
    beam_width = Keyword.fetch!(opts, :beam_width)
    temperature = Keyword.fetch!(opts, :temperature)
    context = Keyword.get(opts, :context)
    model = Keyword.get(opts, :model)

    prompt = build_proposal_prompt(problem, parent_state, beam_width)
    call_llm(prompt, beam_width, temperature, model, context)
  end

  defp build_sampling_prompt(problem, parent_state, k) do
    """
    Problem: #{problem}

    Current state: #{inspect(parent_state, pretty: true)}

    Generate #{k} diverse approaches to solve this problem.
    Each approach should be distinct and explore a different strategy.

    Format each thought as a clear, actionable step.
    """
  end

  defp build_proposal_prompt(problem, parent_state, k) do
    """
    Problem: #{problem}

    Current state: #{inspect(parent_state, pretty: true)}

    Generate #{k} sequential thought proposals to solve this problem.
    Each proposal should build on understanding from previous proposals.
    Proposals should be deliberate and coherent.

    Format each thought as a clear, actionable step.
    """
  end

  defp call_llm(prompt, beam_width, temperature, model_str, _context) do
    system_message = """
    You are an expert reasoning assistant helping to explore multiple solution paths.
    Generate exactly #{beam_width} distinct thoughts or approaches to solve the given problem.

    Return your response as a JSON array of strings, where each string is a complete thought.
    Example: ["First approach...", "Second approach...", "Third approach..."]

    Each thought should be clear, actionable, and distinct from the others.
    """

    # Build model (default to openai:gpt-4 if not specified)
    model = build_model(model_str || "openai:gpt-4")

    # Build ReqLLM model tuple with options
    reqllm_model =
      {model.provider, model.model,
       [
         temperature: temperature,
         max_tokens: 2000
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
          content = ReqLLM.Response.text(response) || ""

          # Try to parse JSON response
          case Jason.decode(content) do
            {:ok, thoughts} when is_list(thoughts) ->
              {:ok, Enum.take(thoughts, beam_width)}

            _ ->
              # If not JSON, split by newlines and filter empty
              thoughts =
                content
                |> String.split("\n")
                |> Enum.map(&String.trim/1)
                |> Enum.reject(&(&1 == "" or String.starts_with?(&1, ["[", "]"])))
                |> Enum.take(beam_width)

              {:ok, thoughts}
          end

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        {:error, {:llm_error, error}}
    end
  end

  # Build a Jido.AI.Model from a model string
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
  Simulates sampling thoughts for testing purposes.

  This function generates fake diverse thoughts without calling an LLM.
  Use this via the `thought_fn` parameter in tests.

  ## Parameters

  - `problem` - The problem being solved
  - `parent_state` - State at parent node
  - `beam_width` - Number of thoughts to generate
  - `temperature` - Temperature setting (unused in simulation)

  ## Returns

  List of simulated thought strings
  """
  @spec simulate_sampling_thoughts(String.t(), map(), pos_integer(), float()) :: list(String.t())
  def simulate_sampling_thoughts(problem, _parent_state, beam_width, _temperature) do
    # Simulate diverse thoughts for testing
    # In production, this would be actual LLM calls

    base_thoughts = [
      "Try a direct calculation approach",
      "Break the problem into smaller sub-problems",
      "Look for patterns or formulas that apply",
      "Work backwards from the desired outcome",
      "Use a systematic elimination strategy",
      "Apply domain-specific knowledge",
      "Consider edge cases and special conditions",
      "Reformulate the problem in a different way"
    ]

    base_thoughts
    |> Enum.take(beam_width)
    |> Enum.with_index()
    |> Enum.map(fn {thought, i} ->
      "#{thought} for: #{String.slice(problem, 0, 30)}... (option #{i + 1})"
    end)
  end

  @doc """
  Simulates proposal thoughts for testing purposes.

  This function generates fake sequential thoughts without calling an LLM.
  Use this via the `thought_fn` parameter in tests.

  ## Parameters

  - `problem` - The problem being solved
  - `parent_state` - State at parent node
  - `beam_width` - Number of thoughts to generate
  - `temperature` - Temperature setting (unused in simulation)

  ## Returns

  List of simulated thought strings
  """
  @spec simulate_proposal_thoughts(String.t(), map(), pos_integer(), float()) :: list(String.t())
  def simulate_proposal_thoughts(problem, _parent_state, beam_width, _temperature) do
    # Simulate sequential proposal thoughts
    # Each builds on understanding from previous

    Enum.map(1..beam_width, fn i ->
      cond do
        i == 1 ->
          "Initial approach: Analyze the problem structure - #{String.slice(problem, 0, 30)}..."

        i == 2 ->
          "Alternative: Based on initial analysis, try a different method"

        i == 3 ->
          "Refined approach: Combine insights from previous proposals"

        true ->
          "Extended approach #{i}: Explore additional variations"
      end
    end)
  end
end
