defmodule Examples.ReAct.BasicMultiHop do
  @moduledoc """
  Basic ReAct example demonstrating multi-hop reasoning with tool use.

  This example shows how ReAct interleaves reasoning (Thought) with actions
  (using tools) and observations (results from tools) to answer questions
  that require information from multiple sources.

  ## Usage

      # Run the example
      Examples.ReAct.BasicMultiHop.run()

      # Run with custom question
      Examples.ReAct.BasicMultiHop.solve_question(
        "What is the capital of the country where the Eiffel Tower is located?"
      )

  ## Features

  - Multi-hop reasoning (question requires multiple steps)
  - Tool-based information gathering
  - Thought-Action-Observation loop
  - Complete trajectory tracking
  """

  require Logger

  @doc """
  Run the complete example with a sample multi-hop question.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  ReAct: Basic Multi-Hop Reasoning Example")
    IO.puts(String.duplicate("=", 70) <> "\n")

    question = "What is the capital of the country where the Eiffel Tower is located?"

    IO.puts("📝 **Question:** #{question}\n")
    IO.puts("🔧 **Available Tools:** search, lookup\n")
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
  Solve a multi-hop question using ReAct reasoning.

  ## Parameters

  - `question` - The question to answer

  ## Returns

  - `{:ok, result}` - Success with answer and trajectory
  - `{:error, reason}` - Failure reason
  """
  def solve_question(question, opts \\ []) do
    max_steps = Keyword.get(opts, :max_steps, 10)

    # Define available tools
    tools = [
      SearchTool,
      LookupTool
    ]

    # Initialize ReAct state
    state = %{
      question: question,
      trajectory: [],
      current_step: 0,
      max_steps: max_steps,
      answer: nil,
      success: false
    }

    # Run the ReAct loop
    run_react_loop(state, tools)
  end

  # Tool Definitions

  defmodule SearchTool do
    @moduledoc """
    Simulated search tool for finding information.
    """

    def name, do: "search"

    def description do
      "Search for information about a topic. Returns relevant facts and details."
    end

    def execute(query) do
      # Simulate search results based on query
      result = case String.downcase(query) do
        q when q =~ "eiffel tower" and (q =~ "location" or q =~ "where") ->
          "The Eiffel Tower is located in Paris, France. It was completed in 1889 and stands 330 meters tall."

        q when q =~ "paris" and q =~ "capital" ->
          "Paris is the capital and largest city of France. It has been France's capital since the 12th century."

        q when q =~ "capital" and q =~ "france" ->
          "The capital of France is Paris, located in the north-central part of the country."

        q when q =~ "tokyo" and q =~ "population" ->
          "Tokyo has a population of approximately 14 million people in the city proper, and about 37 million in the Greater Tokyo Area."

        q when q =~ "mount everest" and q =~ "height" ->
          "Mount Everest stands at 8,849 meters (29,032 feet) above sea level, making it the highest mountain on Earth."

        _ ->
          "Search completed, but no specific information found for: #{query}"
      end

      {:ok, result}
    end
  end

  defmodule LookupTool do
    @moduledoc """
    Simulated lookup tool for extracting specific details from previous observations.
    """

    def name, do: "lookup"

    def description do
      "Look up specific details from previous search results. Use when you need to extract a particular fact."
    end

    def execute(detail) do
      # Simulate looking up details
      result = case String.downcase(detail) do
        d when d =~ "capital" ->
          "Paris"

        d when d =~ "country" ->
          "France"

        d when d =~ "population" ->
          "14 million"

        d when d =~ "height" ->
          "8,849 meters"

        _ ->
          "Could not find specific detail: #{detail}"
      end

      {:ok, result}
    end
  end

  # ReAct Loop Implementation

  defp run_react_loop(state, tools) do
    cond do
      state.answer != nil ->
        # Found answer, stop
        {:ok, finalize_result(state, :answer_found)}

      state.current_step >= state.max_steps ->
        # Reached max steps
        {:ok, finalize_result(state, :max_steps_reached)}

      true ->
        # Continue reasoning
        case execute_step(state, tools) do
          {:ok, new_state} ->
            run_react_loop(new_state, tools)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp execute_step(state, tools) do
    step_number = state.current_step + 1

    IO.puts("🤔 **Step #{step_number}:**")

    # Generate thought
    thought = generate_thought(state, tools)
    IO.puts("   Thought: #{thought}")

    # Parse thought to extract action
    case parse_action(thought) do
      {:final_answer, answer} ->
        IO.puts("   ✅ Final Answer: #{answer}\n")

        step = %{
          step_number: step_number,
          thought: thought,
          action: nil,
          action_input: nil,
          observation: nil,
          final_answer: answer
        }

        {:ok,
         %{
           state
           | current_step: step_number,
             trajectory: state.trajectory ++ [step],
             answer: answer,
             success: true
         }}

      {:action, action_name, action_input} ->
        IO.puts("   Action: #{action_name}(\"#{action_input}\")")

        # Execute the action
        case execute_action(action_name, action_input, tools) do
          {:ok, observation} ->
            IO.puts("   Observation: #{observation}\n")

            step = %{
              step_number: step_number,
              thought: thought,
              action: action_name,
              action_input: action_input,
              observation: observation,
              final_answer: nil
            }

            {:ok,
             %{
               state
               | current_step: step_number,
                 trajectory: state.trajectory ++ [step]
             }}

          {:error, reason} ->
            IO.puts("   ❌ Action failed: #{reason}\n")

            observation = "Error: #{reason}"

            step = %{
              step_number: step_number,
              thought: thought,
              action: action_name,
              action_input: action_input,
              observation: observation,
              final_answer: nil
            }

            {:ok,
             %{
               state
               | current_step: step_number,
                 trajectory: state.trajectory ++ [step]
             }}
        end

      {:error, reason} ->
        {:error, {:thought_parsing_failed, reason}}
    end
  end

  defp generate_thought(state, tools) do
    # Simulate thought generation based on current state
    # In production, this would call an LLM

    cond do
      state.current_step == 0 ->
        # First step - analyze the question
        if String.contains?(state.question, "Eiffel Tower") do
          "I need to find where the Eiffel Tower is located first."
        else
          "I need to gather information to answer this question."
        end

      length(state.trajectory) > 0 ->
        last_step = List.last(state.trajectory)

        cond do
          last_step.observation =~ "Paris, France" and state.question =~ "capital" ->
            "I found that the Eiffel Tower is in Paris, France. Now I need to confirm that Paris is the capital of France."

          last_step.observation =~ "capital" and last_step.observation =~ "Paris" ->
            "I have confirmed that Paris is the capital of France, and the Eiffel Tower is in Paris. I can now provide the final answer."

          true ->
            "Based on the previous observation, I need to continue gathering information."
        end

      true ->
        "Let me search for relevant information."
    end
  end

  defp parse_action(thought) do
    # Simulate action parsing from thought
    # In production, this would use the LLM to generate structured output

    cond do
      thought =~ "can now provide the final answer" or thought =~ "I have confirmed" ->
        if thought =~ "Paris" do
          {:final_answer, "Paris"}
        else
          {:final_answer, "Unknown"}
        end

      thought =~ "where the Eiffel Tower is located" ->
        {:action, "search", "Eiffel Tower location"}

      thought =~ "confirm that Paris is the capital" ->
        {:action, "search", "capital of France"}

      thought =~ "need to find" ->
        {:action, "search", extract_search_query(thought)}

      true ->
        {:action, "search", "general information"}
    end
  end

  defp extract_search_query(thought) do
    # Extract search query from thought
    cond do
      thought =~ "Eiffel Tower" -> "Eiffel Tower location"
      thought =~ "capital" -> "capital information"
      true -> "relevant information"
    end
  end

  defp execute_action(action_name, action_input, tools) do
    tool = Enum.find(tools, fn t -> t.name() == action_name end)

    if tool do
      tool.execute(action_input)
    else
      {:error, "Unknown tool: #{action_name}"}
    end
  end

  defp finalize_result(state, reason) do
    %{
      question: state.question,
      answer: state.answer,
      steps: state.current_step,
      trajectory: state.trajectory,
      success: state.success,
      reason: reason,
      metadata: %{
        max_steps: state.max_steps,
        tools_used: count_tools_used(state.trajectory)
      }
    }
  end

  defp count_tools_used(trajectory) do
    trajectory
    |> Enum.filter(fn step -> step.action != nil end)
    |> Enum.group_by(fn step -> step.action end)
    |> Enum.map(fn {action, steps} -> {action, length(steps)} end)
    |> Enum.into(%{})
  end

  # Display Functions

  defp display_result(result) do
    IO.puts(String.duplicate("=", 70))
    IO.puts("\n✅ **ReAct Execution Complete**\n")

    IO.puts("📊 **Results:**")
    IO.puts("   • Answer: #{result.answer || "Not found"}")
    IO.puts("   • Steps taken: #{result.steps}")
    IO.puts("   • Success: #{result.success}")
    IO.puts("   • Reason: #{result.reason}")

    IO.puts("\n🔧 **Tools Used:**")

    if map_size(result.metadata.tools_used) > 0 do
      Enum.each(result.metadata.tools_used, fn {tool, count} ->
        IO.puts("   • #{tool}: #{count} times")
      end)
    else
      IO.puts("   • No tools used")
    end

    IO.puts("\n📜 **Reasoning Trajectory:**")

    Enum.each(result.trajectory, fn step ->
      IO.puts("\n   Step #{step.step_number}:")
      IO.puts("   Thought: #{step.thought}")

      if step.action do
        IO.puts("   Action: #{step.action}(\"#{step.action_input}\")")
        IO.puts("   Observation: #{step.observation}")
      end

      if step.final_answer do
        IO.puts("   Final Answer: #{step.final_answer}")
      end
    end)

    IO.puts("\n" <> String.duplicate("=", 70))
  end

  @doc """
  Compare with direct answer (without reasoning).
  """
  def compare_with_without_react do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Comparison: Direct vs ReAct")
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

    IO.puts("\n**WITH ReAct (Reasoning + Acting):**")

    {:ok, result} = solve_question(question)

    IO.puts("Question: #{question}")
    IO.puts("Answer: #{result.answer}")
    IO.puts("\nBenefits:")
    IO.puts("  ✓ Clear reasoning trail")
    IO.puts("  ✓ Verifiable information sources")
    IO.puts("  ✓ Step-by-step transparency")
    IO.puts("  ✓ Tool usage tracking")
    IO.puts("  ✓ Reduced hallucination through grounded observations")
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
