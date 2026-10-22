defmodule Jido.AI.Reasoning.Adaptive.SelectionTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Reasoning.Adaptive.Selection, as: Adaptive

  # Retained analysis cases from the v2 Strategy suite.
  test "classifies simple prompts" do
    {strategy, score, task_type} = Adaptive.analyze_prompt("What is the capital of France?")

    assert strategy == :cod
    assert score < 0.3
    assert task_type == :simple_query
  end

  test "classifies tool-use prompts" do
    {strategy, _score, task_type} =
      Adaptive.analyze_prompt("Search for the latest news about AI and fetch the top 5 results.")

    assert strategy == :react
    assert task_type == :tool_use
  end

  test "classifies complex exploration prompts" do
    # Exploration keywords without synthesis keywords
    {strategy, score, task_type} =
      Adaptive.analyze_prompt("""
      Analyze the following complex problem step by step.
      Consider the ethical implications, economic factors, and social consequences.
      Explore alternative solutions and compare their trade-offs.
      You must evaluate each option against the following criteria:
      1. Cost effectiveness
      2. Scalability
      3. Environmental impact
      4. Social acceptance
      What are the multiple options we should consider?
      """)

    assert strategy == :tot
    assert score > 0.7
    assert task_type == :exploration
  end

  test "classifies synthesis prompts for GoT" do
    # Synthesis keywords should select GoT
    {strategy, _score, task_type} =
      Adaptive.analyze_prompt("""
      Synthesize the following viewpoints into a unified recommendation.
      Combine the insights from marketing, engineering, and finance teams.
      Integrate their perspectives to create a comprehensive strategy.
      """)

    assert strategy == :got
    assert task_type == :synthesis
  end

  test "classifies moderate complexity prompts" do
    # A moderately complex prompt without tool keywords but more structure
    prompt = """
    I need to implement a sorting algorithm. The algorithm should work efficiently
    for large datasets. It must handle edge cases like empty arrays and single elements.
    The implementation should also track the number of comparisons made.
    """

    {strategy, score, _task_type} = Adaptive.analyze_prompt(prompt)

    # Moderate complexity score (between thresholds)
    assert score >= 0.3 and score <= 0.7, "Score #{score} should be between 0.3 and 0.7"
    # Without tool keywords, should select based on complexity - moderate goes to react
    assert strategy == :react
  end

  test "respects available strategies" do
    config = %{available_strategies: [:cot, :tot]}

    # Tool-use prompt, but ReAct not available
    {strategy, _score, _task_type} =
      Adaptive.analyze_prompt("Search for information", config)

    # Should fall back to available strategy
    assert strategy in [:cot, :tot]
  end

  test "longer prompts have higher complexity" do
    short = "What is 2+2?"
    long = String.duplicate("This is a complex multi-sentence prompt. ", 20)

    {_strat1, score1, _type1} = Adaptive.analyze_prompt(short)
    {_strat2, score2, _type2} = Adaptive.analyze_prompt(long)

    assert score2 > score1
  end

  test "prompts with constraints have higher complexity" do
    simple = "Tell me about cats."

    constrained =
      "You must explain cats. You need to include their history. You should also mention their behavior. You have to be thorough."

    {_strat1, score1, _type1} = Adaptive.analyze_prompt(simple)
    {_strat2, score2, _type2} = Adaptive.analyze_prompt(constrained)

    assert score2 > score1
  end

  test "prompts with multiple questions have higher complexity" do
    single = "What is Python?"

    multiple =
      "What is Python? How does it compare to Java? Which should I learn? What are the job prospects?"

    {_strat1, score1, _type1} = Adaptive.analyze_prompt(single)
    {_strat2, score2, _type2} = Adaptive.analyze_prompt(multiple)

    assert score2 > score1
  end

  test "detects tool-use from keywords" do
    prompts = [
      "Search for information about climate change",
      "Find the best restaurants nearby",
      "Lookup the definition of this word",
      "Fetch the latest stock prices",
      "Calculate the total cost",
      "Execute this query",
      "Run the analysis tool"
    ]

    for prompt <- prompts do
      {strategy, _score, task_type} = Adaptive.analyze_prompt(prompt)
      assert task_type == :tool_use, "Expected tool_use for: #{prompt}"
      assert strategy == :react, "Expected :react for tool-use prompt: #{prompt}"
    end
  end

  test "detects exploration from keywords" do
    prompts = [
      "Analyze the implications of this decision",
      "Explore different approaches to solving this",
      "Consider multiple options for the design",
      "Compare and contrast these alternatives",
      "Evaluate the different strategies"
    ]

    for prompt <- prompts do
      {_strategy, _score, task_type} = Adaptive.analyze_prompt(prompt)
      assert task_type == :exploration, "Expected exploration for: #{prompt}"
    end
  end

  test "detects simple queries" do
    prompts = [
      "What is machine learning?",
      "Who invented the telephone?",
      "When was Python created?",
      "Where is the Eiffel Tower?",
      "Define recursion",
      "Explain how databases work",
      "Tell me about cats"
    ]

    for prompt <- prompts do
      {_strategy, _score, task_type} = Adaptive.analyze_prompt(prompt)
      assert task_type == :simple_query, "Expected simple_query for: #{prompt}"
    end
  end

  test "falls back to first available when preferred not available" do
    config = %{
      available_strategies: [:cot, :tot],
      complexity_thresholds: %{simple: 0.3, complex: 0.7}
    }

    # Moderate complexity normally selects :react, but it's not available
    prompt = "Help me with this moderately complex task that requires some steps."
    {strategy, _score, _type} = Adaptive.analyze_prompt(prompt, config)

    assert strategy in [:cot, :tot]
  end

  test "detects synthesis from keywords" do
    prompts = [
      "Synthesize these findings into a report",
      "Combine the results from all teams",
      "Merge these different approaches",
      "Integrate the feedback from stakeholders",
      "Aggregate the data from multiple sources"
    ]

    for prompt <- prompts do
      {strategy, _score, task_type} = Adaptive.analyze_prompt(prompt)
      assert task_type == :synthesis, "Expected synthesis for: #{prompt}"
      assert strategy == :got, "Expected :got for synthesis prompt: #{prompt}"
    end
  end

  test "detects graph-related tasks from keywords" do
    prompts = [
      "Map the relationships between these entities",
      "Identify connections in the data",
      "Analyze the network of dependencies",
      "Explore how these are linked together"
    ]

    for prompt <- prompts do
      {strategy, _score, task_type} = Adaptive.analyze_prompt(prompt)
      assert task_type == :synthesis, "Expected synthesis for: #{prompt}"
      assert strategy == :got, "Expected :got for graph-related prompt: #{prompt}"
    end
  end

  test "detects iterative reasoning from puzzle keywords" do
    # Each prompt should contain at least one puzzle keyword:
    # puzzle, iterate, improve, refine, recursive, riddle
    prompts = [
      "This is a puzzle that needs careful reasoning",
      "Iterate on this solution until perfect",
      "Improve the answer through multiple refinements",
      "Refine this draft recursively",
      "This riddle needs careful reasoning"
    ]

    for prompt <- prompts do
      {strategy, _score, task_type} = Adaptive.analyze_prompt(prompt)
      assert task_type == :iterative_reasoning, "Expected iterative_reasoning for: #{prompt}"
      assert strategy == :trm, "Expected :trm for puzzle prompt: #{prompt}"
    end
  end
end
