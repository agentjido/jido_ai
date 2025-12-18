defmodule Examples.ChainOfThoughtExample do
  @moduledoc """
  Practical example demonstrating Chain-of-Thought reasoning usage.

  Chain-of-Thought (CoT) is a prompting technique that encourages LLMs to break down
  complex problems into intermediate reasoning steps, leading to more accurate and
  explainable results.

  ## Basic Usage

      # Simple reasoning task
      {:ok, result} = Examples.ChainOfThoughtExample.solve_with_reasoning(
        problem: "If a train travels 120 km in 2 hours, how far will it travel in 5 hours?",
        use_cot: true
      )

      IO.puts(result.answer)
      IO.puts(result.reasoning)

  ## Comparison Without CoT

      # Without CoT - direct answer
      {:ok, direct} = Examples.ChainOfThoughtExample.solve_with_reasoning(
        problem: "Calculate 15% of 80",
        use_cot: false
      )

      # With CoT - shows reasoning steps
      {:ok, cot} = Examples.ChainOfThoughtExample.solve_with_reasoning(
        problem: "Calculate 15% of 80",
        use_cot: true
      )

      # CoT typically produces more accurate results with explainable steps

  ## Advanced Usage - Multi-Step Planning

      {:ok, result} = Examples.ChainOfThoughtExample.plan_complex_task(
        task: "Build a REST API for a todo application",
        requirements: ["user authentication", "CRUD operations", "data persistence"]
      )

      IO.inspect(result.steps, label: "Planning Steps")
      IO.inspect(result.dependencies, label: "Dependencies")
      IO.inspect(result.estimated_time, label: "Time Estimate")

  ## Features

  - Step-by-step reasoning for complex problems
  - Explainable AI outputs with reasoning traces
  - Improved accuracy on multi-step tasks
  - Planning and decomposition of complex goals
  - Validation through reasoning verification
  """

  require Logger

  alias Jido.AI.Runner.ChainOfThought

  @doc """
  Solve a problem with or without Chain-of-Thought reasoning.

  Demonstrates the difference between direct prompting and CoT prompting.
  With CoT enabled, the LLM breaks down the problem into steps before answering.

  ## Parameters

  - `:problem` - Problem statement or question to solve
  - `:use_cot` - Enable Chain-of-Thought reasoning (default: true)
  - `:model` - LLM model to use (default: "gpt-4")
  - `:temperature` - Sampling temperature (default: 0.7)

  ## Returns

  - `{:ok, result}` with:
    - `:answer` - Final answer
    - `:reasoning` - Step-by-step reasoning (if CoT enabled)
    - `:confidence` - Confidence score (0.0-1.0)
    - `:execution_time` - Time taken in milliseconds

  ## Examples

      # Math problem with reasoning
      {:ok, result} = solve_with_reasoning(
        problem: "A store has 45 apples. If 3/5 are sold, how many remain?",
        use_cot: true
      )

      # Output:
      # %{
      #   answer: "18 apples remain",
      #   reasoning: \"\"\"
      #     Step 1: Calculate 3/5 of 45
      #       3/5 * 45 = 27 apples sold
      #     Step 2: Subtract from total
      #       45 - 27 = 18 apples
      #     Therefore, 18 apples remain.
      #   \"\"\",
      #   confidence: 0.95,
      #   execution_time: 1234
      # }
  """
  @spec solve_with_reasoning(keyword()) :: {:ok, map()} | {:error, term()}
  def solve_with_reasoning(opts) do
    problem = Keyword.fetch!(opts, :problem)
    use_cot = Keyword.get(opts, :use_cot, true)
    model = Keyword.get(opts, :model, "gpt-4")
    temperature = Keyword.get(opts, :temperature, 0.7)

    Logger.info("Solving problem with CoT=#{use_cot}: #{problem}")

    start_time = System.monotonic_time(:millisecond)

    # Build prompt based on CoT setting
    prompt = if use_cot do
      build_cot_prompt(problem)
    else
      build_direct_prompt(problem)
    end

    # Execute with ChainOfThought runner
    result = case ChainOfThought.execute(
      prompt: prompt,
      model: model,
      temperature: temperature,
      reasoning_type: if(use_cot, do: :step_by_step, else: :direct)
    ) do
      {:ok, response} ->
        execution_time = System.monotonic_time(:millisecond) - start_time

        parsed = if use_cot do
          parse_cot_response(response)
        else
          parse_direct_response(response)
        end

        {:ok, Map.put(parsed, :execution_time, execution_time)}

      {:error, reason} ->
        {:error, reason}
    end

    Logger.info("Solution completed in #{elem(result, 1)[:execution_time] || 0}ms")
    result
  end

  @doc """
  Plan a complex task using Chain-of-Thought decomposition.

  Breaks down a high-level task into concrete steps with dependencies,
  time estimates, and potential issues.

  ## Parameters

  - `:task` - High-level task description
  - `:requirements` - List of requirements or constraints
  - `:context` - Additional context (optional)

  ## Returns

  - `{:ok, plan}` with:
    - `:steps` - Ordered list of steps with descriptions
    - `:dependencies` - Dependencies between steps
    - `:estimated_time` - Time estimate per step
    - `:potential_issues` - Identified risks or challenges
    - `:recommendations` - Optimization suggestions

  ## Examples

      {:ok, plan} = plan_complex_task(
        task: "Implement user authentication system",
        requirements: [
          "JWT tokens",
          "Password hashing",
          "Email verification",
          "OAuth integration"
        ],
        context: "Building a SaaS application"
      )

      Enum.each(plan.steps, fn step ->
        IO.puts("\#{step.number}. \#{step.description}")
        IO.puts("   Time: \#{step.estimated_time}")
        IO.puts("   Dependencies: \#{inspect(step.dependencies)}")
      end)
  """
  @spec plan_complex_task(keyword()) :: {:ok, map()} | {:error, term()}
  def plan_complex_task(opts) do
    task = Keyword.fetch!(opts, :task)
    requirements = Keyword.get(opts, :requirements, [])
    context = Keyword.get(opts, :context, "")

    Logger.info("Planning complex task: #{task}")

    # Build planning prompt with CoT structure
    prompt = """
    Task: #{task}

    Requirements:
    #{Enum.map_join(requirements, "\n", fn req -> "- #{req}" end)}

    #{if context != "", do: "Context: #{context}\n", else: ""}

    Please break down this task into concrete steps using chain-of-thought reasoning:

    1. Analyze the requirements and identify main components
    2. Break down into sequential steps with clear deliverables
    3. Identify dependencies between steps
    4. Estimate time for each step
    5. Highlight potential issues or risks
    6. Provide recommendations for optimization

    Format your response as:
    ## Analysis
    [Your analysis of requirements]

    ## Steps
    1. [Step description]
       - Time: [estimate]
       - Dependencies: [list]
       - Deliverable: [what is produced]

    ## Dependencies
    [Dependency graph or explanation]

    ## Potential Issues
    [Risks and challenges]

    ## Recommendations
    [Optimization suggestions]
    """

    case ChainOfThought.execute(
      prompt: prompt,
      model: "gpt-4",
      temperature: 0.3,  # Lower temperature for planning
      reasoning_type: :step_by_step
    ) do
      {:ok, response} ->
        plan = parse_planning_response(response)
        Logger.info("Created plan with #{length(plan.steps)} steps")
        {:ok, plan}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Analyze a decision using Chain-of-Thought reasoning.

  Uses CoT to evaluate options, weigh pros/cons, and make a recommendation
  with clear reasoning.

  ## Parameters

  - `:decision` - Decision to be made
  - `:options` - List of options to consider
  - `:criteria` - Evaluation criteria (optional)

  ## Returns

  - `{:ok, analysis}` with:
    - `:recommendation` - Recommended option
    - `:reasoning` - Step-by-step analysis
    - `:comparison` - Pros/cons comparison
    - `:confidence` - Confidence in recommendation

  ## Examples

      {:ok, analysis} = analyze_decision(
        decision: "Choose a database for our application",
        options: ["PostgreSQL", "MongoDB", "DynamoDB"],
        criteria: ["performance", "scalability", "cost", "ease of use"]
      )

      IO.puts("Recommendation: \#{analysis.recommendation}")
      IO.puts("\nReasoning:")
      IO.puts(analysis.reasoning)
      IO.puts("\nConfidence: \#{analysis.confidence}")
  """
  @spec analyze_decision(keyword()) :: {:ok, map()} | {:error, term()}
  def analyze_decision(opts) do
    decision = Keyword.fetch!(opts, :decision)
    options = Keyword.fetch!(opts, :options)
    criteria = Keyword.get(opts, :criteria, [])

    Logger.info("Analyzing decision: #{decision}")

    prompt = """
    Decision to Make: #{decision}

    Options:
    #{Enum.map_join(options, "\n", fn opt -> "- #{opt}" end)}

    #{if length(criteria) > 0 do
      "Evaluation Criteria:\n" <> Enum.map_join(criteria, "\n", fn c -> "- #{c}" end)
    else
      ""
    end}

    Please analyze this decision using chain-of-thought reasoning:

    1. Understand the decision context and requirements
    2. Evaluate each option against the criteria
    3. Compare pros and cons
    4. Consider trade-offs and implications
    5. Make a recommendation with clear justification

    Provide structured reasoning showing your analysis process.
    """

    case ChainOfThought.execute(
      prompt: prompt,
      model: "gpt-4",
      temperature: 0.5,
      reasoning_type: :step_by_step
    ) do
      {:ok, response} ->
        analysis = parse_decision_response(response, options)
        {:ok, analysis}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Verify reasoning steps for correctness.

  Uses a secondary CoT pass to validate the reasoning chain and identify
  any logical errors or gaps.

  ## Parameters

  - `:reasoning` - Reasoning chain to verify
  - `:problem` - Original problem statement
  - `:answer` - Proposed answer

  ## Returns

  - `{:ok, verification}` with:
    - `:is_valid` - Boolean indicating if reasoning is sound
    - `:issues` - List of identified issues (if any)
    - `:suggestions` - Improvement suggestions
    - `:confidence` - Confidence in verification

  ## Examples

      {:ok, solution} = solve_with_reasoning(
        problem: "Calculate compound interest",
        use_cot: true
      )

      {:ok, verification} = verify_reasoning(
        reasoning: solution.reasoning,
        problem: "Calculate compound interest",
        answer: solution.answer
      )

      if verification.is_valid do
        IO.puts("Reasoning verified!")
      else
        IO.puts("Issues found:")
        Enum.each(verification.issues, &IO.puts/1)
      end
  """
  @spec verify_reasoning(keyword()) :: {:ok, map()} | {:error, term()}
  def verify_reasoning(opts) do
    reasoning = Keyword.fetch!(opts, :reasoning)
    problem = Keyword.fetch!(opts, :problem)
    answer = Keyword.fetch!(opts, :answer)

    Logger.info("Verifying reasoning for problem: #{problem}")

    prompt = """
    Problem: #{problem}

    Reasoning Provided:
    #{reasoning}

    Answer: #{answer}

    Please verify this reasoning using chain-of-thought analysis:

    1. Check each step for logical correctness
    2. Verify calculations or deductions
    3. Identify any gaps or unsupported claims
    4. Validate the final answer follows from the reasoning
    5. Suggest improvements if needed

    Provide structured verification:
    - Is the reasoning sound? (Yes/No)
    - Issues found (if any)
    - Suggestions for improvement
    """

    case ChainOfThought.execute(
      prompt: prompt,
      model: "gpt-4",
      temperature: 0.2,  # Low temperature for verification
      reasoning_type: :verification
    ) do
      {:ok, response} ->
        verification = parse_verification_response(response)
        {:ok, verification}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Compare performance with and without Chain-of-Thought.

  Runs the same problem both ways and compares accuracy, reasoning quality,
  and execution time.

  ## Examples

      {:ok, comparison} = compare_with_without_cot(
        problem: "If 3 workers can build a wall in 6 days, how long will it take 9 workers?"
      )

      IO.puts("Without CoT:")
      IO.puts("  Answer: \#{comparison.without_cot.answer}")
      IO.puts("  Time: \#{comparison.without_cot.execution_time}ms")

      IO.puts("\nWith CoT:")
      IO.puts("  Answer: \#{comparison.with_cot.answer}")
      IO.puts("  Reasoning: \#{comparison.with_cot.reasoning}")
      IO.puts("  Time: \#{comparison.with_cot.execution_time}ms")

      IO.puts("\nAccuracy improvement: \#{comparison.accuracy_improvement}%")
  """
  @spec compare_with_without_cot(keyword()) :: {:ok, map()} | {:error, term()}
  def compare_with_without_cot(opts) do
    problem = Keyword.fetch!(opts, :problem)

    Logger.info("Comparing CoT vs Direct for: #{problem}")

    # Run without CoT
    {:ok, without_cot} = solve_with_reasoning(problem: problem, use_cot: false)

    # Run with CoT
    {:ok, with_cot} = solve_with_reasoning(problem: problem, use_cot: true)

    # Compare results
    comparison = %{
      problem: problem,
      without_cot: without_cot,
      with_cot: with_cot,
      accuracy_improvement: calculate_accuracy_improvement(without_cot, with_cot),
      time_overhead: with_cot.execution_time - without_cot.execution_time,
      recommendation: if(with_cot.confidence > without_cot.confidence, do: :use_cot, else: :direct)
    }

    {:ok, comparison}
  end

  # Private helper functions

  defp build_cot_prompt(problem) do
    """
    Problem: #{problem}

    Let's solve this step by step:
    1. First, understand what we're being asked
    2. Break down the problem into parts
    3. Solve each part
    4. Combine for the final answer

    Please show your reasoning for each step.
    """
  end

  defp build_direct_prompt(problem) do
    """
    Problem: #{problem}

    Please provide the answer.
    """
  end

  defp parse_cot_response(response) do
    # In real implementation, would parse the LLM response
    # For example purposes, return structured result
    %{
      answer: extract_answer(response),
      reasoning: extract_reasoning(response),
      confidence: calculate_confidence(response)
    }
  end

  defp parse_direct_response(response) do
    %{
      answer: extract_answer(response),
      reasoning: "",
      confidence: 0.7  # Lower confidence without explicit reasoning
    }
  end

  defp parse_planning_response(response) do
    # Parse structured planning response
    %{
      analysis: extract_section(response, "Analysis"),
      steps: extract_steps(response),
      dependencies: extract_dependencies(response),
      potential_issues: extract_section(response, "Potential Issues"),
      recommendations: extract_section(response, "Recommendations")
    }
  end

  defp parse_decision_response(response, options) do
    %{
      recommendation: extract_recommendation(response, options),
      reasoning: extract_reasoning(response),
      comparison: extract_comparison(response),
      confidence: calculate_confidence(response)
    }
  end

  defp parse_verification_response(response) do
    %{
      is_valid: check_if_valid(response),
      issues: extract_issues(response),
      suggestions: extract_suggestions(response),
      confidence: calculate_confidence(response)
    }
  end

  defp extract_answer(response) do
    # Placeholder - would parse actual LLM response
    String.slice(response, 0..100)
  end

  defp extract_reasoning(response) do
    # Placeholder - would extract reasoning steps
    response
  end

  defp calculate_confidence(_response) do
    # Placeholder - would analyze response for confidence indicators
    0.85
  end

  defp extract_section(response, section_name) do
    # Placeholder - would parse section from response
    "#{section_name} content from response"
  end

  defp extract_steps(response) do
    # Placeholder - would parse steps
    [
      %{number: 1, description: "Step 1", estimated_time: "2 hours", dependencies: []},
      %{number: 2, description: "Step 2", estimated_time: "4 hours", dependencies: [1]}
    ]
  end

  defp extract_dependencies(_response) do
    "Step 2 depends on Step 1"
  end

  defp extract_recommendation(response, options) do
    # Placeholder - would extract recommended option
    List.first(options)
  end

  defp extract_comparison(_response) do
    # Placeholder - would extract pros/cons comparison
    %{pros: [], cons: []}
  end

  defp check_if_valid(response) do
    # Placeholder - would check validity in response
    String.contains?(response, "Yes") or String.contains?(response, "valid")
  end

  defp extract_issues(_response) do
    # Placeholder - would extract identified issues
    []
  end

  defp extract_suggestions(_response) do
    # Placeholder - would extract suggestions
    []
  end

  defp calculate_accuracy_improvement(without_cot, with_cot) do
    # Placeholder - would calculate based on ground truth
    improvement = (with_cot.confidence - without_cot.confidence) * 100
    Float.round(improvement, 1)
  end
end
