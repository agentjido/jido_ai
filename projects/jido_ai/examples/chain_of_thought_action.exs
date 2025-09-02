# Chain of Thought Action with LLM Integration
#
# This action implements an intelligent chain of thought pattern by:
# 1. Using LLM to analyze the problem
# 2. Breaking it into steps using AI reasoning
# 3. Enqueuing follow-up actions to execute each step

defmodule ChainOfThoughtAction do
  @moduledoc """
  A Chain of Thought action that uses LLM to break down complex problems into steps
  and enqueues follow-up actions to execute them sequentially.
  """

  use Jido.Action,
    name: "chain_of_thought",
    description: "Uses LLM to break down complex problems into steps and enqueue follow-up actions",
    schema: [
      problem: [type: :string, required: true, doc: "The problem to break down"],
      max_steps: [type: :integer, default: 3, doc: "Maximum number of steps to create"],
      context_key: [type: :string, default: "cot_session", doc: "Key to store context between steps"],
      model: [type: :string, default: "openai:gpt-4o-mini", doc: "LLM model to use for reasoning"]
    ]

  alias Jido.Agent.Directive

  @spec run(map(), map()) :: {:ok, map(), list(Directive.Enqueue.t())}
  def run(%{problem: problem} = params, context) do
    max_steps = Map.get(params, :max_steps, 3)
    context_key = Map.get(params, :context_key, "cot_session")
    model = Map.get(params, :model, "openai:gpt-4o-mini")
    session_id = :crypto.strong_rand_bytes(8) |> Base.encode16()

    # Use LLM to understand the problem and plan the approach
    prompt = """
    I need to solve this problem using a systematic chain of thought approach: #{problem}
    
    Please provide a brief initial analysis of this problem in 1-2 sentences. What is the core challenge here?
    """

    case Jido.AI.generate_text(model, prompt) do
      {:ok, initial_analysis} ->
        # Step 1: Start the chain with LLM-powered analysis
        analysis_step = %Directive.Enqueue{
          action: AnalyzeProblemAction,
          params: %{
            problem: problem,
            session_id: session_id,
            step_number: 1,
            max_steps: max_steps,
            model: model,
            initial_analysis: initial_analysis
          },
          context: Map.put(context, context_key, %{
            problem: problem,
            session_id: session_id,
            steps_completed: 0,
            max_steps: max_steps,
            model: model,
            initial_analysis: initial_analysis
          })
        }

        {:ok, %{
          session_id: session_id,
          problem: problem,
          max_steps: max_steps,
          model: model,
          initial_analysis: initial_analysis,
          status: "initiated"
        }, [analysis_step]}

      {:error, reason} ->
        {:ok, %{
          session_id: session_id,
          problem: problem,
          status: "failed",
          error: "Failed to get initial analysis: #{inspect(reason)}"
        }}
    end
  end
end

defmodule AnalyzeProblemAction do
  @moduledoc """
  Uses LLM to analyze a problem and create the next step in the chain of thought.
  """

  use Jido.Action,
    name: "analyze_problem", 
    description: "Uses LLM to analyze a problem and determine the next step",
    schema: [
      problem: [type: :string, required: true],
      session_id: [type: :string, required: true],
      step_number: [type: :integer, required: true],
      max_steps: [type: :integer, required: true],
      model: [type: :string, required: true],
      initial_analysis: [type: :string, required: false]
    ]

  alias Jido.Agent.Directive

  @spec run(map(), map()) :: {:ok, map(), list(Directive.Enqueue.t())}
  def run(%{problem: problem, session_id: session_id, step_number: step, max_steps: max_steps, model: model} = params, context) do
    initial_analysis = Map.get(params, :initial_analysis, "")
    
    # Use LLM to analyze the current step
    prompt = """
    Chain of Thought Analysis - Step #{step} of #{max_steps}
    
    Problem: #{problem}
    #{if initial_analysis != "", do: "Initial Analysis: #{initial_analysis}", else: ""}
    
    Based on this problem, what should step #{step} focus on? Provide:
    1. A brief description of what to analyze in this step
    2. The specific action or approach for this step
    3. Your reasoning for why this step is important
    
    Keep it concise - 2-3 sentences total.
    """

    case Jido.AI.generate_text(model, prompt) do
      {:ok, llm_analysis} ->
        # Parse the LLM response to extract key information
        step_description = extract_step_description(llm_analysis, step)
        
        # Create next step if we haven't reached max
        next_actions = if step < max_steps do
          [%Directive.Enqueue{
            action: ExecuteStepAction,
            params: %{
              session_id: session_id,
              step_number: step + 1,
              step_description: step_description,
              problem: problem,
              max_steps: max_steps,
              model: model,
              llm_analysis: llm_analysis
            },
            context: context
          }]
        else
          [%Directive.Enqueue{
            action: SummarizeSolutionAction,
            params: %{
              session_id: session_id,
              problem: problem,
              total_steps: step,
              model: model,
              final_analysis: llm_analysis
            },
            context: context
          }]
        end

        {:ok, %{
          session_id: session_id,
          step_number: step,
          llm_analysis: llm_analysis,
          step_description: step_description,
          status: "analyzed"
        }, next_actions}

      {:error, reason} ->
        {:ok, %{
          session_id: session_id,
          step_number: step,
          status: "failed", 
          error: "Failed to analyze step: #{inspect(reason)}"
        }}
    end
  end

  defp extract_step_description(llm_response, step) do
    # Simple extraction - in a real implementation you might use more sophisticated parsing
    case String.split(llm_response, "\n") |> Enum.find(&String.contains?(&1, ["step", "Step", "focus", "approach"])) do
      nil -> "Execute step #{step} of the problem-solving process"
      line -> String.trim(line)
    end
  end


end

defmodule ExecuteStepAction do
  @moduledoc """
  Uses LLM to execute a specific step in the chain of thought process.
  """

  use Jido.Action,
    name: "execute_step",
    description: "Uses LLM to execute a specific step in the problem-solving process",
    schema: [
      session_id: [type: :string, required: true],
      step_number: [type: :integer, required: true], 
      step_description: [type: :string, required: true],
      problem: [type: :string, required: true],
      max_steps: [type: :integer, required: true],
      model: [type: :string, required: true],
      llm_analysis: [type: :string, required: false]
    ]

  alias Jido.Agent.Directive

  @spec run(map(), map()) :: {:ok, map(), list(Directive.Enqueue.t())}
  def run(%{session_id: session_id, step_number: step, step_description: description, problem: problem, max_steps: max_steps, model: model} = params, context) do
    llm_analysis = Map.get(params, :llm_analysis, "")
    
    # Use LLM to execute this step
    prompt = """
    Chain of Thought Execution - Step #{step} of #{max_steps}
    
    Problem: #{problem}
    Step Focus: #{description}
    #{if llm_analysis != "", do: "Previous Analysis: #{llm_analysis}", else: ""}
    
    Now execute this step. Provide:
    1. Your specific approach for this step
    2. Key insights or findings from this step
    3. How this step moves us closer to solving the problem
    
    Be concrete and actionable. Keep it to 3-4 sentences.
    """

    case Jido.AI.generate_text(model, prompt) do
      {:ok, execution_result} ->
        # Parse execution result
        insights = extract_insights(execution_result)
        
        # Determine if we should continue or summarize
        next_actions = if step < max_steps do
          [%Directive.Enqueue{
            action: AnalyzeProblemAction,
            params: %{
              problem: problem,
              session_id: session_id,
              step_number: step + 1,
              max_steps: max_steps,
              model: model,
              previous_step_result: execution_result
            },
            context: context
          }]
        else
          [%Directive.Enqueue{
            action: SummarizeSolutionAction,
            params: %{
              session_id: session_id,
              problem: problem,
              total_steps: step,
              model: model,
              final_step_result: execution_result
            },
            context: context
          }]
        end

        {:ok, %{
          session_id: session_id,
          step_number: step,
          description: description,
          execution_result: execution_result,
          insights: insights,
          status: "step_completed"
        }, next_actions}

      {:error, reason} ->
        {:ok, %{
          session_id: session_id,
          step_number: step,
          status: "failed",
          error: "Failed to execute step: #{inspect(reason)}"
        }}
    end
  end

  defp extract_insights(execution_result) do
    # Simple extraction - look for key insights in the result
    execution_result
    |> String.split([".", "!", "\n"])
    |> Enum.map(&String.trim/1)
    |> Enum.filter(fn line -> 
      String.length(line) > 10 and 
      (String.contains?(line, ["insight", "key", "important", "approach", "solution"]) or String.match?(line, ~r/^\d+\./))
    end)
    |> Enum.take(3)
  end


end

defmodule SummarizeSolutionAction do
  @moduledoc """
  Uses LLM to summarize the complete chain of thought solution.
  """

  use Jido.Action,
    name: "summarize_solution",
    description: "Uses LLM to summarize the complete chain of thought solution",
    schema: [
      session_id: [type: :string, required: true],
      problem: [type: :string, required: true],
      total_steps: [type: :integer, required: true],
      model: [type: :string, required: true],
      final_analysis: [type: :string, required: false],
      final_step_result: [type: :string, required: false]
    ]

  @spec run(map(), map()) :: {:ok, map()}
  def run(%{session_id: session_id, problem: problem, total_steps: steps, model: model} = params, _context) do
    final_analysis = Map.get(params, :final_analysis, "")
    final_step_result = Map.get(params, :final_step_result, "")
    
    # Use LLM to create a comprehensive summary
    prompt = """
    Chain of Thought Summary
    
    Original Problem: #{problem}
    Steps Completed: #{steps}
    #{if final_analysis != "", do: "Final Analysis: #{final_analysis}", else: ""}
    #{if final_step_result != "", do: "Final Step Result: #{final_step_result}", else: ""}
    
    Please provide a comprehensive summary that includes:
    1. The key insights discovered through this chain of thought process
    2. The recommended solution or approach
    3. Any important considerations or next steps
    
    Format this as a clear, actionable summary.
    """

    case Jido.AI.generate_text(model, prompt) do
      {:ok, llm_summary} ->
        {:ok, %{
          session_id: session_id,
          problem: problem,
          total_steps: steps,
          summary: llm_summary,
          final_analysis: final_analysis,
          final_step_result: final_step_result,
          status: "completed",
          chain_completed_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }}

      {:error, reason} ->
        # Fallback to basic summary if LLM fails
        basic_summary = create_fallback_summary(problem, steps)
        
        {:ok, %{
          session_id: session_id,
          problem: problem,
          total_steps: steps,
          summary: basic_summary,
          status: "completed_with_fallback",
          error: "LLM summary failed: #{inspect(reason)}",
          chain_completed_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }}
    end
  end

  defp create_fallback_summary(problem, steps) do
    """
    Chain of Thought Summary (Fallback):
    
    Problem: #{problem}
    
    Solution Process (#{steps} steps):
    1. Analyzed and understood the problem requirements
    2. Broke down the problem into manageable components  
    3. Identified optimal solution approaches for each component
    
    Key Insights:
    - Systematic breakdown enables better problem solving
    - Each step builds upon the previous analysis
    - Iterative approach ensures thorough coverage
    
    Final Recommendation: 
    Implement the solution using the identified components and approaches,
    with proper validation at each step.
    
    Note: This is a basic summary as LLM integration was unavailable.
    """
  end
end
