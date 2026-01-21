defmodule Examples.ReAct.AdvancedResearchAgent do
  @moduledoc """
  Advanced ReAct example demonstrating a research agent with multiple tool types using the ReAct runner.

  This example shows more sophisticated ReAct patterns including:
  - Multiple specialized tools (search, calculator, database, fact_check)
  - ReAct runner orchestration
  - Jido Action-based tools
  - Error handling through runner
  - Complex multi-step research workflows
  - Result aggregation and synthesis

  ## Agent-Based Architecture

  Uses the ReAct runner with specialized Jido Actions:
  - SearchTool: Web search simulation
  - CalculatorTool: Mathematical operations
  - DatabaseTool: Structured data queries
  - FactCheckTool: Information verification

  ## Usage

      # Run the complete example
      Examples.ReAct.AdvancedResearchAgent.run()

      # Research a topic
      Examples.ReAct.AdvancedResearchAgent.research_topic(
        "What is the GDP per capita of France?"
      )

  ## Features

  - Multiple Jido Action tools (search, calculate, database, fact_check)
  - ReAct runner orchestration
  - Error recovery via runner
  - Result synthesis from multiple sources
  - Confidence scoring
  - Tool usage tracking
  """

  require Logger

  alias Jido.AI.Runner.ReAct

  @doc """
  Run the complete research agent example using the ReAct runner.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("  Advanced ReAct Research Agent (Runner-Based)")
    IO.puts(String.duplicate("=", 80) <> "\n")

    # Research question requiring multiple tool types
    question = "What is France's GDP, and how does its GDP per capita compare to Germany's?"

    IO.puts("🔬 **Research Question:**")
    IO.puts("   #{question}\n")

    IO.puts("🧰 **Available Tools:**")
    IO.puts("   • search - Web search for information")
    IO.puts("   • calculate - Mathematical calculations")
    IO.puts("   • database - Query structured data")
    IO.puts("   • fact_check - Verify information accuracy\n")

    IO.puts("🔧 **Method:** ReAct runner with Jido Action tools\n")
    IO.puts(String.duplicate("-", 80) <> "\n")

    case research_topic(question) do
      {:ok, result} ->
        display_result(result)
        {:ok, result}

      {:error, reason} ->
        IO.puts("❌ **Research Failed:** #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Research a topic using the ReAct runner with multiple specialized tools.

  ## Parameters

  - `question` - The research question to investigate
  - `opts` - Options:
    - `:max_steps` - Maximum reasoning steps (default: 20)
    - `:temperature` - Temperature for thought generation (default: 0.7)

  ## Returns

  - `{:ok, result}` - Success with research findings and trajectory
  - `{:error, reason}` - Failure reason
  """
  def research_topic(question, opts \\ []) do
    max_steps = Keyword.get(opts, :max_steps, 20)
    temperature = Keyword.get(opts, :temperature, 0.7)

    IO.puts("🚀 **Running Research with ReAct runner...**\n")

    # Define available tools as Jido Actions
    tools = [
      SearchTool,
      CalculatorTool,
      DatabaseTool,
      FactCheckTool
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
    @moduledoc "Web search tool for finding information (Jido Action)."

    use Jido.Action,
      name: "search",
      description:
        "Search the web for information. Returns relevant facts, statistics, and details about the query.",
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

      # Simulate web search
      result =
        cond do
          String.contains?(q, "france") and String.contains?(q, "gdp") ->
            """
            France GDP Information:
            • Total GDP: $2.96 trillion (2023)
            • GDP Growth: 2.5% (2023)
            • Population: 67.8 million
            • GDP per capita: approximately $43,659
            """

          String.contains?(q, "germany") and String.contains?(q, "gdp") ->
            """
            Germany GDP Information:
            • Total GDP: $4.31 trillion (2023)
            • GDP Growth: -0.3% (2023)
            • Population: 83.3 million
            • GDP per capita: approximately $51,761
            """

          String.contains?(q, "gdp per capita") and String.contains?(q, "calculation") ->
            """
            GDP per capita is calculated by dividing a country's total GDP
            by its population. Formula: GDP per capita = Total GDP / Population
            """

          String.contains?(q, "economic comparison") ->
            """
            When comparing economies, consider:
            • GDP per capita (standard of living)
            • GDP growth rate (economic momentum)
            • Purchasing power parity (real value)
            • Employment rates and productivity
            """

          true ->
            "Search completed for: #{query}. Limited results found."
        end

      {:ok, result}
    end
  end

  defmodule CalculatorTool do
    @moduledoc "Mathematical calculator for numerical operations (Jido Action)."

    use Jido.Action,
      name: "calculate",
      description:
        "Perform mathematical calculations. Supports arithmetic, percentages, ratios, and comparisons.",
      schema: [
        expression: [
          type: :string,
          required: true,
          doc: "The mathematical expression to evaluate"
        ]
      ]

    def run(params, _context) do
      expression = Map.get(params, :expression, "")
      expr = String.downcase(expression)

      # Simulate calculation
      result =
        cond do
          String.contains?(expr, "2.96") and String.contains?(expr, "67.8") ->
            # France GDP per capita
            value = 2.96 / 67.8 * 1_000_000
            {:ok, "#{Float.round(value, 2)} - France's GDP per capita"}

          String.contains?(expr, "4.31") and String.contains?(expr, "83.3") ->
            # Germany GDP per capita
            value = 4.31 / 83.3 * 1_000_000
            {:ok, "#{Float.round(value, 2)} - Germany's GDP per capita"}

          String.contains?(expr, "51761") and String.contains?(expr, "43659") ->
            # Comparison
            difference = 51761 - 43659
            percentage = (difference / 43659) * 100
            {:ok, "Germany's GDP per capita is $#{difference} higher (#{Float.round(percentage, 1)}% more)"}

          String.contains?(expr, "percentage") or String.contains?(expr, "%") ->
            {:ok, "Percentage calculation completed"}

          true ->
            # Generic calculation
            try do
              # Sanitize and evaluate basic arithmetic
              sanitized = String.replace(expression, ~r/[^0-9+\-*\/.()]/, "")
              {calc_result, _} = Code.eval_string(sanitized)
              {:ok, "Result: #{calc_result}"}
            rescue
              _ -> {:error, "Invalid expression: #{expression}"}
            end
        end

      result
    end
  end

  defmodule DatabaseTool do
    @moduledoc "Database query tool for structured economic data (Jido Action)."

    use Jido.Action,
      name: "database",
      description:
        "Query structured database for economic statistics, historical data, and verified facts.",
      schema: [
        query: [
          type: :string,
          required: true,
          doc: "SQL-like query or structured data request"
        ]
      ]

    def run(params, _context) do
      query = Map.get(params, :query, "")
      q = String.downcase(query)

      # Simulate database query
      result =
        cond do
          String.contains?(q, "gdp") and String.contains?(q, "france") ->
            """
            Database Query Results:
            Country: France
            Year: 2023
            GDP (USD): 2,960,000,000,000
            Population: 67,800,000
            GDP_per_capita: 43,659
            Source: World Bank, IMF
            Last Updated: 2024-01
            """

          String.contains?(q, "gdp") and String.contains?(q, "germany") ->
            """
            Database Query Results:
            Country: Germany
            Year: 2023
            GDP (USD): 4,310,000,000,000
            Population: 83,300,000
            GDP_per_capita: 51,761
            Source: World Bank, IMF
            Last Updated: 2024-01
            """

          String.contains?(q, "comparison") ->
            """
            Database Comparison Results:
            France GDP per capita: $43,659
            Germany GDP per capita: $51,761
            Difference: $8,102 (18.6% higher)
            Ranking: Germany #4, France #7 (EU)
            """

          true ->
            "No matching records found for query: #{query}"
        end

      {:ok, result}
    end
  end

  defmodule FactCheckTool do
    @moduledoc "Fact checking tool to verify information accuracy (Jido Action)."

    use Jido.Action,
      name: "fact_check",
      description:
        "Verify the accuracy of claims and cross-reference information from multiple sources.",
      schema: [
        claim: [
          type: :string,
          required: true,
          doc: "The claim or fact to verify"
        ]
      ]

    def run(params, _context) do
      claim = Map.get(params, :claim, "")
      c = String.downcase(claim)

      # Simulate fact checking
      result =
        cond do
          String.contains?(c, "france") and String.contains?(c, "2.96 trillion") ->
            """
            ✓ VERIFIED: France's GDP is approximately $2.96 trillion (2023)
            Sources: World Bank, IMF, OECD
            Confidence: High (95%)
            Last Verified: 2024-01
            """

          String.contains?(c, "germany") and String.contains?(c, "4.31 trillion") ->
            """
            ✓ VERIFIED: Germany's GDP is approximately $4.31 trillion (2023)
            Sources: World Bank, IMF, Destatis
            Confidence: High (95%)
            Last Verified: 2024-01
            """

          String.contains?(c, "51,761") or String.contains?(c, "51761") ->
            """
            ✓ VERIFIED: Germany's GDP per capita is approximately $51,761
            Calculation: $4.31T / 83.3M
            Sources: World Bank data
            Confidence: High (90%)
            """

          String.contains?(c, "43,659") or String.contains?(c, "43659") ->
            """
            ✓ VERIFIED: France's GDP per capita is approximately $43,659
            Calculation: $2.96T / 67.8M
            Sources: World Bank data
            Confidence: High (90%)
            """

          true ->
            """
            ⚠ UNCERTAIN: Could not verify claim
            Reason: Insufficient sources or conflicting data
            Recommendation: Gather more information
            """
        end

      {:ok, result}
    end
  end

  # Display Functions

  defp display_result(result) do
    IO.puts(String.duplicate("=", 80))
    IO.puts("\n✅ **Research Complete (via ReAct Runner)**\n")

    IO.puts("📊 **Summary:**")
    IO.puts("   • Steps taken: #{result.steps}")
    IO.puts("   • Success: #{result.success}")
    IO.puts("   • Reason: #{result.reason}")
    IO.puts("   • Trajectory length: #{length(result.trajectory)}")

    IO.puts("\n🔧 **Tools Used:**")

    tools_used = result.metadata.tools_used

    if map_size(tools_used) > 0 do
      Enum.each(tools_used, fn {tool, count} ->
        IO.puts("   • #{tool}: #{count} times")
      end)
    else
      IO.puts("   • No tools used")
    end

    IO.puts("\n💡 **Answer:**")
    IO.puts(String.trim(result.answer || "No answer found"))

    IO.puts("\n📜 **Research Trajectory:**")

    Enum.each(result.trajectory, fn step ->
      IO.puts("\n   📍 Step #{step.step_number}:")
      IO.puts("      💭 #{step.thought}")

      if step.action do
        IO.puts("      🔧 #{step.action}(\"#{step.action_input}\")")
        observation_preview = String.slice(step.observation, 0, 80)
        IO.puts("      📝 #{observation_preview}...")
      end

      if step.final_answer do
        answer_preview = String.slice(step.final_answer, 0, 80)
        IO.puts("      ✅ #{answer_preview}...")
      end
    end)

    IO.puts("\n" <> String.duplicate("=", 80))
  end

  @doc """
  Demonstrate error handling and recovery benefits of the ReAct runner.
  """
  def demonstrate_error_handling do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("  Error Handling & Recovery Demo")
    IO.puts(String.duplicate("=", 80) <> "\n")

    # Describe error handling capabilities
    IO.puts("Scenario: Tool failures during research\n")

    IO.puts("✓ Benefits of ReAct Runner error handling:")
    IO.puts("  • Failed tools generate observations (not crashes)")
    IO.puts("  • Runner can try alternative tools")
    IO.puts("  • Built-in error recovery")
    IO.puts("  • Graceful degradation")
    IO.puts("  • Complete trajectory even with errors")
    IO.puts("  • Jido Action-based tool system")
  end
end
