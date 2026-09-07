defmodule Jido.AI.Reasoning.Adaptive.Selection do
  @moduledoc false
  alias Jido.AI.{Profile, Reasoning}

  @methods %{
    cod: :chain_of_draft,
    cot: :chain_of_thought,
    react: :react,
    aot: :algorithm_of_thoughts,
    tot: :tree_of_thoughts,
    got: :graph_of_thoughts,
    trm: :trm
  }
  @default_thresholds %{simple: 0.3, complex: 0.7}
  @defaults %{
    available_strategies: [:cod, :cot, :react, :tot, :got, :trm],
    complexity_thresholds: @default_thresholds,
    strategy_override: nil,
    method_options: %{}
  }

  # Keywords that suggest specific strategies
  @tool_keywords ~w(search find lookup fetch get calculate compute call execute run use tool)
  @complex_keywords ~w(analyze explore consider multiple options alternatives compare contrast evaluate)
  @simple_keywords ~w(what is who when where define explain tell me)
  # Keywords that suggest graph-based reasoning (GoT)
  @synthesis_keywords ~w(synthesize combine merge integrate aggregate unify consolidate)
  @graph_keywords ~w(relationships connections network graph linked interdependent perspectives viewpoints)
  # Keywords that suggest iterative reasoning (TRM)
  # Note: multi-word keywords use spaces, and we check for both with and without hyphens
  @puzzle_keywords ~w(puzzle iterate improve refine recursive riddle)

  def options(value) do
    with {:ok, value} <- Profile.fields(value, Map.keys(@defaults), "reasoning.options"),
         options = Map.merge(@defaults, value),
         available = options.available_strategies,
         true <- is_list(available) and available != [] and available == Enum.uniq(available),
         true <- Enum.all?(available, &Map.has_key?(@methods, &1)),
         true <- is_nil(options.strategy_override) or options.strategy_override in available,
         {:ok, thresholds} <-
           Profile.fields(
             options.complexity_thresholds,
             [:simple, :complex],
             "reasoning.options.complexity_thresholds"
           ),
         thresholds = Map.merge(@default_thresholds, thresholds),
         true <- Enum.all?(Map.values(thresholds), &(is_number(&1) and &1 >= 0 and &1 <= 1)),
         true <- thresholds.simple <= thresholds.complex,
         {:ok, methods} <-
           Profile.fields(
             options.method_options,
             Map.keys(@methods),
             "reasoning.options.method_options"
           ),
         {:ok, methods} <-
           Profile.traverse(Enum.to_list(methods), fn {method, opts} ->
             with {:ok, opts} <- Reasoning.options(@methods[method], opts),
                  do: {:ok, {method, opts}}
           end) do
      {:ok, %{options | complexity_thresholds: thresholds, method_options: Map.new(methods)}}
    else
      false ->
        Profile.error(
          "reasoning.options",
          "Expected known available methods, an available override, and ordered thresholds from 0 to 1"
        )

      error ->
        error
    end
  end

  def select(profile, query) when is_binary(query) do
    options = profile.reasoning.options

    {strategy, score, task_type} =
      if options.strategy_override,
        do: {options.strategy_override, 0.5, :manual_override},
        else: analyze_prompt(query, options)

    selection = %{
      strategy: strategy,
      method: @methods[strategy],
      complexity_score: score,
      task_type: task_type,
      source: if(options.strategy_override, do: :override, else: :automatic)
    }

    reasoning = %{
      profile.reasoning
      | method: selection.method,
        options: Map.get(options.method_options, strategy, %{})
    }

    tools = if selection.method in [:react, :tree_of_thoughts], do: profile.tools, else: []

    instructions =
      if selection.method == :react and is_nil(profile.instructions),
        do: Jido.AI.Reasoning.react_prompt(),
        else: profile.instructions

    with {:ok, selected} <-
           Profile.new(%{
             profile
             | reasoning: reasoning,
               tools: tools,
               instructions: instructions
           }),
         {:ok, selected} <- Profile.resolve_controls(selected),
         do: {:ok, selected, selection}
  end

  def select(_, _),
    do: Profile.error("query", "Adaptive selection currently requires a text query")

  def analyze_prompt(prompt, config \\ %{}) do
    thresholds = Map.get(config, :complexity_thresholds, @default_thresholds)
    available = Map.get(config, :available_strategies, [:cod, :cot, :react, :tot, :got, :trm])

    # Calculate complexity score
    complexity_score = calculate_complexity(prompt)

    # Detect task type from keywords
    task_type = detect_task_type(prompt)

    # Select strategy based on analysis
    strategy = select_strategy(complexity_score, task_type, thresholds, available)

    {strategy, complexity_score, task_type}
  end

  defp calculate_complexity(prompt) do
    # Normalize prompt
    prompt_lower = String.downcase(prompt)
    words = String.split(prompt_lower, ~r/\s+/)
    word_count = length(words)

    # Base complexity from length
    length_score = min(word_count / 100, 1.0) * 0.3

    # Complexity from sentence structure
    sentence_count = length(String.split(prompt, ~r/[.!?]+/)) - 1
    structure_score = min(sentence_count / 5, 1.0) * 0.2

    # Complexity from keywords
    complex_keyword_count =
      Enum.count(@complex_keywords, fn kw ->
        String.contains?(prompt_lower, kw)
      end)

    keyword_score = min(complex_keyword_count / 3, 1.0) * 0.3

    # Complexity from questions and constraints
    question_count = length(Regex.scan(~r/\?/, prompt))
    constraint_patterns = ~r/(must|should|need to|have to|require)/i
    constraint_count = length(Regex.scan(constraint_patterns, prompt))
    constraint_score = min((question_count + constraint_count) / 5, 1.0) * 0.2

    # Total score
    min(length_score + structure_score + keyword_score + constraint_score, 1.0)
  end

  defp detect_task_type(prompt) do
    prompt_lower = String.downcase(prompt)

    cond do
      # Iterative reasoning/puzzle tasks prefer TRM
      has_puzzle_keywords?(prompt_lower) ->
        :iterative_reasoning

      # Synthesis/graph tasks prefer GoT
      has_synthesis_keywords?(prompt_lower) ->
        :synthesis

      has_tool_keywords?(prompt_lower) ->
        :tool_use

      has_complex_keywords?(prompt_lower) ->
        :exploration

      has_simple_keywords?(prompt_lower) ->
        :simple_query

      true ->
        :general
    end
  end

  defp has_tool_keywords?(prompt) do
    Enum.any?(@tool_keywords, &String.contains?(prompt, &1))
  end

  defp has_complex_keywords?(prompt) do
    Enum.any?(@complex_keywords, &String.contains?(prompt, &1))
  end

  defp has_simple_keywords?(prompt) do
    Enum.any?(@simple_keywords, &String.contains?(prompt, &1))
  end

  defp has_synthesis_keywords?(prompt) do
    Enum.any?(@synthesis_keywords, &String.contains?(prompt, &1)) or
      Enum.any?(@graph_keywords, &String.contains?(prompt, &1))
  end

  defp has_puzzle_keywords?(prompt) do
    Enum.any?(@puzzle_keywords, &String.contains?(prompt, &1))
  end

  defp select_strategy(complexity_score, task_type, thresholds, available) do
    # First, check task type overrides
    strategy = select_by_task_type(task_type, available)

    # If no task-type override, use complexity score
    strategy = strategy || select_by_complexity(complexity_score, thresholds, available)

    # Final fallback
    strategy || :react
  end

  defp select_by_task_type(:tool_use, available) do
    if :react in available, do: :react
  end

  defp select_by_task_type(:synthesis, available) do
    # Synthesis tasks prefer GoT for combining multiple perspectives
    find_first_available([:got, :tot], available)
  end

  defp select_by_task_type(:exploration, available) do
    # Exploration tasks prefer AoT when available, then ToT/GoT.
    find_first_available([:aot, :tot, :got], available)
  end

  defp select_by_task_type(:iterative_reasoning, available) do
    # Iterative reasoning/puzzle tasks prefer TRM for recursive improvement
    find_first_available([:trm, :tot], available)
  end

  defp select_by_task_type(_other, _available), do: nil

  defp select_by_complexity(score, thresholds, available) do
    cond do
      score < thresholds.simple ->
        find_first_available([:cod, :cot], available) || List.first(available)

      score > thresholds.complex ->
        find_first_available([:aot, :tot, :got], available) || List.first(available)

      true ->
        find_first_available([:react], available) || List.first(available)
    end
  end

  defp find_first_available(preferences, available) do
    Enum.find(preferences, fn pref -> pref in available end)
  end
end
