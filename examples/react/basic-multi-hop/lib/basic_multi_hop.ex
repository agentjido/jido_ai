defmodule Examples.ReAct.BasicMultiHop do
  @moduledoc """
  Basic ReAct example demonstrating multi-hop reasoning with tool use using the ReAct runner.

  This example shows how ReAct interleaves reasoning (Thought) with actions
  (using tools) and observations (results from tools) to answer questions
  that require information from multiple sources.

  ## Agent-Based Architecture

  Uses the ReAct runner with Jido Actions as tools:
  - SearchTool: Web search simulation
  - LookupTool: Detail extraction from previous results

  ## Usage

      # Run the example
      Examples.ReAct.BasicMultiHop.run()

      # Run with custom question
      Examples.ReAct.BasicMultiHop.solve_question(
        "What is the capital of the country where the Eiffel Tower is located?"
      )

  ## Features

  - Multi-hop reasoning (question requires multiple steps)
  - Jido Action-based tools
  - ReAct runner orchestration
  - Thought-Action-Observation loop
  - Complete trajectory tracking
  """

  require Logger

  alias Jido.AI.Runner.ReAct

  @doc """
  Run the complete example with a sample multi-hop question.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  ReAct: Basic Multi-Hop Reasoning Example (Runner-Based)")
    IO.puts(String.duplicate("=", 70) <> "\n")

    question = "What is the capital of the country where the Eiffel Tower is located?"

    IO.puts("📝 **Question:** #{question}\n")
    IO.puts("🔧 **Available Tools:** search, lookup\n")
    IO.puts("🔧 **Method:** ReAct runner with tool execution\n")
    IO.puts(String.duplicate("-", 70) <> "\n")

    case solve_question(question) do
      {:ok, result} ->
        display_result(result)
        {:ok, result}

      {:error, reason} ->
        IO.puts("❌ **Error:** #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Solve a multi-hop question using ReAct reasoning with the ReAct runner.

  ## Parameters

  - `question` - The question to answer
  - `opts` - Options:
    - `:max_steps` - Maximum reasoning steps (default: 10)
    - `:temperature` - Temperature for thought generation (default: 0.7)

  ## Returns

  - `{:ok, result}` - Success with answer and trajectory
  - `{:error, reason}` - Failure reason
  """
  def solve_question(question, opts \\ []) do
    max_steps = Keyword.get(opts, :max_steps, 10)
    temperature = Keyword.get(opts, :temperature, 0.7)

    IO.puts("🚀 **Running ReAct with runner...**\n")

    # Define available tools as Jido Actions
    tools = [
      SearchTool,
      LookupTool
    ]

    # Call the ReAct runner
    ReAct.run(
      question: question,
      tools: tools,
      max_steps: max_steps,
      temperature: temperature
    )
  end

  # Tool Definitions (Jido Actions for ReAct runner)

  defmodule SearchTool do
    @moduledoc """
    Search tool for finding information (Jido Action).
    """

    use Jido.Action,
      name: "search",
      description: "Search for information about a topic. Returns relevant facts and details.",
      schema: [
        query: [
          type: :string,
          required: true,
          doc: "The search query or topic to research"
        ]
      ]

    def run(params, _context) do
      query = Map.get(params, :query, "")
      q = String.downcase(query)

      # Simulate search results based on query
      result =
        cond do
          String.contains?(q, "eiffel tower") and (String.contains?(q, "location") or String.contains?(q, "where")) ->
            "The Eiffel Tower is located in Paris, France. It was completed in 1889 and stands 330 meters tall."

          String.contains?(q, "paris") and String.contains?(q, "capital") ->
            "Paris is the capital and largest city of France. It has been France's capital since the 12th century."

          String.contains?(q, "capital") and String.contains?(q, "france") ->
            "The capital of France is Paris, located in the north-central part of the country."

          String.contains?(q, "tokyo") and String.contains?(q, "population") ->
            "Tokyo has a population of approximately 14 million people in the city proper, and about 37 million in the Greater Tokyo Area."

          String.contains?(q, "mount everest") and String.contains?(q, "height") ->
            "Mount Everest stands at 8,849 meters (29,032 feet) above sea level, making it the highest mountain on Earth."

          true ->
            "Search completed, but no specific information found for: #{query}"
        end

      {:ok, result}
    end
  end

  defmodule LookupTool do
    @moduledoc """
    Lookup tool for extracting specific details (Jido Action).
    """

    use Jido.Action,
      name: "lookup",
      description:
        "Look up specific details from previous search results. Use when you need to extract a particular fact.",
      schema: [
        detail: [
          type: :string,
          required: true,
          doc: "The specific detail to look up"
        ]
      ]

    def run(params, _context) do
      detail = Map.get(params, :detail, "")
      d = String.downcase(detail)

      # Simulate looking up details
      result =
        cond do
          String.contains?(d, "capital") ->
            "Paris"

          String.contains?(d, "country") ->
            "France"

          String.contains?(d, "population") ->
            "14 million"

          String.contains?(d, "height") ->
            "8,849 meters"

          true ->
            "Could not find specific detail: #{detail}"
        end

      {:ok, result}
    end
  end

  # Display Functions

  defp display_result(result) do
    IO.puts(String.duplicate("=", 70))
    IO.puts("\n✅ **ReAct Execution Complete (via Runner)**\n")

    IO.puts("📊 **Results:**")
    IO.puts("   • Answer: #{result.answer || "Not found"}")
    IO.puts("   • Steps taken: #{result.steps}")
    IO.puts("   • Success: #{result.success}")
    IO.puts("   • Reason: #{result.reason}")

    IO.puts("\n🔧 **Tools Used:**")

    tools_used = result.metadata.tools_used

    if map_size(tools_used) > 0 do
      Enum.each(tools_used, fn {tool, count} ->
        IO.puts("   • #{tool}: #{count} times")
      end)
    else
      IO.puts("   • No tools used")
    end

    IO.puts("\n📜 **Reasoning Trajectory (#{length(result.trajectory)} steps):**")

    Enum.each(result.trajectory, fn step ->
      IO.puts("\n   📍 Step #{step.step_number}:")
      IO.puts("      💭 #{step.thought}")

      if step.action do
        IO.puts("      🔧 #{step.action}(\"#{step.action_input}\")")
        IO.puts("      📝 #{step.observation}")
      end

      if step.final_answer do
        IO.puts("      ✅ Final Answer: #{step.final_answer}")
      end
    end)

    IO.puts("\n" <> String.duplicate("=", 70))
  end

  @doc """
  Compare with direct answer (without reasoning).
  """
  def compare_with_without_react do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Comparison: Direct vs ReAct Runner")
    IO.puts(String.duplicate("=", 70) <> "\n")

    question = "What is the capital of the country where the Eiffel Tower is located?"

    IO.puts("**WITHOUT ReAct (Direct Answer):**")
    IO.puts("Question: #{question}")
    IO.puts("Answer: Paris (but no reasoning trail)")
    IO.puts("Issues:")
    IO.puts("  • No explanation of how answer was found")
    IO.puts("  • Cannot verify reasoning steps")
    IO.puts("  • Prone to hallucination")
    IO.puts("  • No visibility into information sources")

    IO.puts("\n**WITH ReAct Runner (Reasoning + Acting):**")

    {:ok, result} = solve_question(question)

    IO.puts("Question: #{question}")
    IO.puts("Answer: #{result.answer}")
    IO.puts("\nBenefits of ReAct Runner:")
    IO.puts("  ✓ Clear reasoning trail via runner")
    IO.puts("  ✓ Verifiable information sources")
    IO.puts("  ✓ Step-by-step transparency")
    IO.puts("  ✓ Tool usage tracking")
    IO.puts("  ✓ Reduced hallucination through grounded observations")
    IO.puts("  ✓ Jido Action-based tool system")
  end

  @doc """
  Try multiple questions to demonstrate the pattern.
  """
  def batch_solve(questions \\ nil) do
    default_questions = [
      "What is the capital of the country where the Eiffel Tower is located?",
      "What is the population of Tokyo?",
      "How tall is Mount Everest?"
    ]

    questions_to_solve = questions || default_questions

    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Batch ReAct Problem Solving")
    IO.puts(String.duplicate("=", 70) <> "\n")

    results =
      Enum.map(questions_to_solve, fn question ->
        IO.puts("Question: #{question}")

        case solve_question(question) do
          {:ok, result} ->
            IO.puts("Answer: #{result.answer}")
            IO.puts("Steps: #{result.steps}")
            IO.puts("")
            result

          {:error, reason} ->
            IO.puts("Error: #{inspect(reason)}\n")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    IO.puts("Solved #{length(results)}/#{length(questions_to_solve)} questions")

    avg_steps =
      if length(results) > 0 do
        results
        |> Enum.map(& &1.steps)
        |> Enum.sum()
        |> Kernel./(length(results))
        |> Float.round(1)
      else
        0.0
      end

    IO.puts("Average steps: #{avg_steps}")

    {:ok, results}
  end
end
