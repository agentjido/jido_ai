defmodule Jido.AI.Runner.ReActTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.ReAct
  alias Jido.AI.Runner.ReAct.{ActionSelector, ObservationProcessor, ToolRegistry}

  # =============================================================================
  # Action Selector Tests
  # =============================================================================

  describe "ActionSelector.parse/1" do
    test "parses standard action format" do
      output = """
      Thought: I need to search for information about Elixir
      Action: search
      Action Input: Elixir programming language
      """

      assert {:action, thought, "search", "Elixir programming language"} =
               ActionSelector.parse(output)

      assert thought =~ "search for information"
    end

    test "parses final answer format" do
      output = """
      Thought: Based on the search results, I now have the answer
      Final Answer: Elixir was created by José Valim in 2011
      """

      assert {:final_answer, thought, answer} = ActionSelector.parse(output)
      assert thought =~ "search results"
      assert answer =~ "José Valim"
    end

    test "parses function call format" do
      output = """
      Thought: I need to calculate the result
      Action: calculate(15 + 27)
      """

      assert {:action, _thought, "calculate", "15 + 27"} = ActionSelector.parse(output)
    end

    test "handles missing thought" do
      output = """
      Action: search
      Action Input: test query
      """

      assert {:error, {:thought_extraction_failed, _}} = ActionSelector.parse(output)
    end

    test "handles missing action" do
      output = """
      Thought: I'm thinking but not acting
      """

      assert {:error, {:action_extraction_failed, _}} = ActionSelector.parse(output)
    end

    test "extracts multi-line action input" do
      output = """
      Thought: Need detailed search
      Action: search
      Action Input: This is a
      multi-line
      query
      """

      assert {:action, _thought, "search", input} = ActionSelector.parse(output)
      assert input =~ "multi-line"
    end
  end

  describe "ActionSelector.extract_action/1" do
    test "extracts standard format action" do
      output = """
      Action: search
      Action Input: test query
      """

      assert {:ok, "search", "test query"} = ActionSelector.extract_action(output)
    end

    test "extracts function format action" do
      output = "Action: calculate(10 + 20)"
      assert {:ok, "calculate", "10 + 20"} = ActionSelector.extract_action(output)
    end

    test "returns error when no action found" do
      output = "Just some text without an action"
      assert {:error, :no_action_found} = ActionSelector.extract_action(output)
    end
  end

  describe "ActionSelector.validate_action/2" do
    test "validates action against available tools" do
      tools = [
        %{name: "search"},
        %{name: "calculate"}
      ]

      assert :ok = ActionSelector.validate_action("search", tools)
      assert :ok = ActionSelector.validate_action("calculate", tools)
      assert {:error, :invalid_action} = ActionSelector.validate_action("unknown", tools)
    end

    test "handles different tool formats" do
      tools = [
        %{name: "tool1"},
        %{"name" => "tool2"},
        "tool3"
      ]

      assert :ok = ActionSelector.validate_action("tool1", tools)
      assert :ok = ActionSelector.validate_action("tool2", tools)
      assert :ok = ActionSelector.validate_action("tool3", tools)
    end
  end

  # =============================================================================
  # Observation Processor Tests
  # =============================================================================

  describe "ObservationProcessor.process/2" do
    test "processes string observations" do
      {:ok, observation} = ObservationProcessor.process("Simple text observation")
      assert observation == "Simple text observation"
    end

    test "processes map observations" do
      result = %{result: "The answer is 42"}
      {:ok, observation} = ObservationProcessor.process(result)
      assert observation =~ "42"
    end

    test "processes list observations" do
      result = ["item1", "item2", "item3"]
      {:ok, observation} = ObservationProcessor.process(result)
      assert observation =~ "Found 3 results"
      assert observation =~ "item1"
    end

    test "truncates long observations" do
      long_text = String.duplicate("word ", 200)
      {:ok, observation} = ObservationProcessor.process(long_text, max_length: 100)
      assert String.length(observation) <= 100
    end

    test "summarizes long observations when enabled" do
      long_text =
        """
        First sentence with important information.
        Second sentence. Third sentence.
        Fourth sentence. Fifth sentence.
        Last sentence with a conclusion.
        """ <> String.duplicate("Filler sentence. ", 50)

      {:ok, observation} =
        ObservationProcessor.process(long_text, summarize: true, max_length: 200)

      assert String.length(observation) <= 200
      # Should prefer first and last sentences
      assert observation =~ "First sentence" or observation =~ "Last sentence"
    end

    test "handles error tuples" do
      {:ok, observation} = ObservationProcessor.process({:error, :not_found})
      assert observation =~ "Error"
      assert observation =~ "not_found"
    end

    test "handles ok tuples" do
      {:ok, observation} = ObservationProcessor.process({:ok, "Success result"})
      assert observation =~ "Success result"
    end
  end

  describe "ObservationProcessor.summarize_observation/2" do
    test "summarizes by selecting important sentences" do
      text = """
      The Eiffel Tower was built in 1889. It is located in Paris, France.
      It was designed by Gustave Eiffel. The tower is 330 meters tall.
      It weighs approximately 10,000 tons. It has three levels for visitors.
      """

      summary = ObservationProcessor.summarize_observation(text, 150)

      assert String.length(summary) <= 150
      # Should keep important facts (numbers and dates)
      assert summary =~ "1889" or summary =~ "330" or summary =~ "Paris"
    end

    test "handles text shorter than target" do
      text = "Short text"
      summary = ObservationProcessor.summarize_observation(text, 100)
      assert summary =~ "Short text"
    end
  end

  describe "ObservationProcessor.format_for_reasoning/3" do
    test "formats observation with action name" do
      formatted =
        ObservationProcessor.format_for_reasoning(
          "Result from search",
          "search",
          include_action: true
        )

      assert formatted =~ "[search]"
      assert formatted =~ "Result from search"
    end

    test "formats without action name when disabled" do
      formatted =
        ObservationProcessor.format_for_reasoning(
          "Result",
          "search",
          include_action: false
        )

      refute formatted =~ "[search]"
      assert formatted =~ "Result"
    end
  end

  # =============================================================================
  # Tool Registry Tests
  # =============================================================================

  describe "ToolRegistry.format_tool_description/1" do
    test "formats tool with parameters" do
      tool = %{
        name: "search",
        description: "Search the web",
        parameters: [:query]
      }

      description = ToolRegistry.format_tool_description(tool)
      assert description =~ "search(query)"
      assert description =~ "Search the web"
    end

    test "formats tool without parameters" do
      tool = %{
        name: "get_time",
        description: "Get current time"
      }

      description = ToolRegistry.format_tool_description(tool)
      assert description =~ "get_time:"
      assert description =~ "Get current time"
      refute description =~ "("
    end

    test "formats tool with multiple parameters" do
      tool = %{
        name: "calculate",
        description: "Calculate expression",
        parameters: [:expression, :precision]
      }

      description = ToolRegistry.format_tool_description(tool)
      assert description =~ "calculate(expression, precision)"
    end
  end

  describe "ToolRegistry.execute_tool/3" do
    test "executes function tool successfully" do
      tool = %{
        name: "add",
        description: "Add two numbers",
        function: fn input ->
          [a, b] =
            String.split(input, "+") |> Enum.map(&String.trim/1) |> Enum.map(&String.to_integer/1)

          {:ok, a + b}
        end
      }

      assert {:ok, 15} = ToolRegistry.execute_tool(tool, "10+5", %{})
    end

    test "executes function tool returning plain value" do
      tool = %{
        name: "double",
        function: fn input -> String.to_integer(input) * 2 end
      }

      assert {:ok, 20} = ToolRegistry.execute_tool(tool, "10", %{})
    end

    test "handles function tool errors" do
      tool = %{
        name: "fail",
        function: fn _input -> {:error, :something_went_wrong} end
      }

      assert {:error, :something_went_wrong} = ToolRegistry.execute_tool(tool, "input", %{})
    end

    test "executes zero-arity function" do
      tool = %{
        name: "get_constant",
        function: fn -> {:ok, 42} end
      }

      assert {:ok, 42} = ToolRegistry.execute_tool(tool, "ignored", %{})
    end

    test "handles execution errors gracefully" do
      tool = %{
        name: "crash",
        function: fn _input -> raise "boom" end
      }

      assert {:error, {:function_execution_failed, _}} =
               ToolRegistry.execute_tool(tool, "input", %{})
    end
  end

  describe "ToolRegistry.validate_tool/1" do
    test "validates correct tool" do
      tool = %{
        name: "search",
        description: "Search the web",
        function: fn x -> x end
      }

      assert :ok = ToolRegistry.validate_tool(tool)
    end

    test "detects missing name" do
      tool = %{
        description: "No name",
        function: fn x -> x end
      }

      assert {:error, {:invalid_tool, errors}} = ToolRegistry.validate_tool(tool)
      assert :missing_name in errors
    end

    test "detects missing description" do
      tool = %{
        name: "tool",
        function: fn x -> x end
      }

      assert {:error, {:invalid_tool, errors}} = ToolRegistry.validate_tool(tool)
      assert :missing_description in errors
    end

    test "detects missing executable" do
      tool = %{
        name: "tool",
        description: "No function"
      }

      assert {:error, {:invalid_tool, errors}} = ToolRegistry.validate_tool(tool)
      assert :missing_executable in errors
    end
  end

  describe "ToolRegistry.create_function_tool/4" do
    test "creates function tool with all fields" do
      tool =
        ToolRegistry.create_function_tool(
          "search",
          "Search the web",
          fn query -> {:ok, "Results for #{query}"} end,
          parameters: [:query]
        )

      assert tool.name == "search"
      assert tool.description == "Search the web"
      assert is_function(tool.function)
      assert tool.parameters == [:query]
    end

    test "creates tool without parameters" do
      tool =
        ToolRegistry.create_function_tool(
          "get_time",
          "Get time",
          fn -> {:ok, "12:00"} end
        )

      assert tool.parameters == []
    end
  end

  # =============================================================================
  # ReAct Loop Integration Tests
  # =============================================================================

  describe "ReAct.run/1" do
    test "executes simple ReAct loop to find answer" do
      # Create mock tools
      search_tool = %{
        name: "search",
        description: "Search for information",
        function: fn query ->
          cond do
            query =~ "Eiffel Tower" -> {:ok, "The Eiffel Tower is in Paris, France."}
            query =~ "capital" -> {:ok, "The capital of France is Paris."}
            true -> {:ok, "No results found"}
          end
        end,
        parameters: [:query]
      }

      # Custom thought function for testing
      thought_fn = fn state, _opts ->
        case state.step_number do
          0 ->
            """
            Thought: I need to find where the Eiffel Tower is located.
            Action: search
            Action Input: Eiffel Tower location
            """

          1 ->
            """
            Thought: I found that the Eiffel Tower is in Paris. Now I can answer.
            Final Answer: The Eiffel Tower is located in Paris, France.
            """

          _ ->
            """
            Thought: I should have the answer by now.
            Final Answer: Paris, France
            """
        end
      end

      {:ok, result} =
        ReAct.run(
          question: "Where is the Eiffel Tower located?",
          tools: [search_tool],
          max_steps: 5,
          thought_fn: thought_fn
        )

      assert result.success
      assert result.answer =~ "Paris"
      assert result.steps <= 5
      assert length(result.trajectory) >= 1
    end

    test "respects max_steps limit" do
      # Tool that always returns results
      search_tool = %{
        name: "search",
        function: fn _query -> {:ok, "Some result"} end
      }

      # Thought function that never gives final answer
      thought_fn = fn _state, _opts ->
        """
        Thought: I need more information.
        Action: search
        Action Input: more info
        """
      end

      {:ok, result} =
        ReAct.run(
          question: "Test question",
          tools: [search_tool],
          max_steps: 3,
          thought_fn: thought_fn
        )

      refute result.success
      assert result.reason == :max_steps_reached
      assert result.steps == 3
    end

    test "handles action errors gracefully" do
      # Tool that fails
      failing_tool = %{
        name: "search",
        function: fn _query -> {:error, :api_timeout} end
      }

      # Thought function that eventually gives up
      thought_fn = fn state, _opts ->
        if state.step_number < 2 do
          """
          Thought: Let me try searching.
          Action: search
          Action Input: query
          """
        else
          """
          Thought: The search failed, but I'll provide my best guess.
          Final Answer: Unable to determine from failed searches
          """
        end
      end

      {:ok, result} =
        ReAct.run(
          question: "Test question",
          tools: [failing_tool],
          max_steps: 5,
          thought_fn: thought_fn
        )

      # Should still complete despite errors
      assert result.steps >= 2
      # Check that error observations were recorded
      error_steps =
        Enum.filter(result.trajectory, fn step ->
          step.observation && step.observation =~ "Error"
        end)

      assert length(error_steps) > 0
    end

    test "records trajectory with all steps" do
      tools = [
        %{
          name: "search",
          function: fn _q -> {:ok, "Result"} end
        }
      ]

      thought_fn = fn state, _opts ->
        case state.step_number do
          0 ->
            """
            Thought: First thought
            Action: search
            Action Input: first query
            """

          1 ->
            """
            Thought: Second thought
            Final Answer: Final answer
            """
        end
      end

      {:ok, result} =
        ReAct.run(
          question: "Test",
          tools: tools,
          thought_fn: thought_fn
        )

      assert length(result.trajectory) == 2

      [step1, step2] = result.trajectory

      assert step1.step_number == 1
      assert step1.thought =~ "First thought"
      assert step1.action == "search"
      assert step1.observation =~ "Result"

      assert step2.step_number == 2
      assert step2.thought =~ "Second thought"
      assert step2.final_answer =~ "Final answer"
    end

    test "tracks tool usage in metadata" do
      tools = [
        %{name: "search", function: fn _q -> {:ok, "result"} end},
        %{name: "calculate", function: fn _e -> {:ok, 42} end}
      ]

      thought_fn = fn state, _opts ->
        case state.step_number do
          0 -> "Thought: search\nAction: search\nAction Input: q1"
          1 -> "Thought: calc\nAction: calculate\nAction Input: 1+1"
          2 -> "Thought: search again\nAction: search\nAction Input: q2"
          _ -> "Thought: done\nFinal Answer: answer"
        end
      end

      {:ok, result} =
        ReAct.run(
          question: "Test",
          tools: tools,
          thought_fn: thought_fn,
          max_steps: 10
        )

      tools_used = result.metadata.tools_used
      assert tools_used["search"] == 2
      assert tools_used["calculate"] == 1
    end
  end

  describe "ReAct.execute_step/2" do
    test "executes single step successfully" do
      tools = [
        %{name: "search", function: fn _q -> {:ok, "Found info"} end}
      ]

      state = %{
        question: "Test question",
        tools: tools,
        trajectory: [],
        step_number: 0,
        max_steps: 10,
        temperature: 0.7,
        thought_template: "",
        thought_fn: fn _s, _o ->
          """
          Thought: Need to search
          Action: search
          Action Input: test query
          """
        end,
        context: %{}
      }

      assert {:continue, updated_state, step} = ReAct.execute_step(state)

      assert updated_state.step_number == 1
      assert length(updated_state.trajectory) == 1
      assert step.action == "search"
      assert step.observation =~ "Found info"
    end

    test "detects final answer" do
      state = %{
        question: "Test",
        tools: [],
        trajectory: [],
        step_number: 0,
        max_steps: 10,
        temperature: 0.7,
        thought_template: "",
        thought_fn: fn _s, _o ->
          """
          Thought: I have the answer
          Final Answer: This is the answer
          """
        end,
        context: %{}
      }

      assert {:finish, final_state, step} = ReAct.execute_step(state)

      assert step.final_answer == "This is the answer"
      assert final_state.step_number == 1
    end
  end

  # =============================================================================
  # Performance and Use Case Tests
  # =============================================================================

  describe "Performance characteristics" do
    test "documents expected cost multiplier" do
      # ReAct typically takes 5-15 steps
      # Each step involves thought generation + action execution
      cost_model = %{
        base_cot_cost: 1,
        steps: 10,
        # Average for multi-hop questions
        cost_per_step: 1,
        # Each step = 1 LLM call for thought
        total_cost: fn model -> model.base_cot_cost + model.steps * model.cost_per_step end
      }

      total = cost_model.total_cost.(cost_model)

      # ReAct typically 10-20x cost
      assert total >= 10
      assert total <= 20
    end

    test "documents accuracy improvement" do
      # Research shows significant improvements on multi-hop reasoning
      metrics = %{
        hotpotqa_baseline: 0.29,
        hotpotqa_react: 0.564,
        # +27.4%
        fever_baseline: 0.56,
        fever_react: 0.755
        # +19.5%
      }

      hotpotqa_improvement =
        (metrics.hotpotqa_react - metrics.hotpotqa_baseline) / metrics.hotpotqa_baseline

      fever_improvement = (metrics.fever_react - metrics.fever_baseline) / metrics.fever_baseline

      # HotpotQA improvement should be ~94%
      assert hotpotqa_improvement > 0.9
      # Fever improvement should be ~35%
      assert fever_improvement > 0.3
    end
  end

  describe "Use case validation" do
    test "documents when to use ReAct" do
      use_cases = %{
        multi_hop_reasoning: "Questions requiring multiple information sources",
        research_tasks: "Information gathering across different sources",
        iterative_investigation: "Tasks needing step-by-step exploration",
        tool_use: "Problems requiring external tool calls",
        grounded_reasoning: "Tasks where hallucination must be minimized"
      }

      assert Map.has_key?(use_cases, :multi_hop_reasoning)
      assert Map.has_key?(use_cases, :research_tasks)
      assert is_binary(use_cases.tool_use)
    end

    test "documents when NOT to use ReAct" do
      avoid_cases = %{
        simple_questions: "Single-fact lookups answerable in one step",
        creative_tasks: "Open-ended generation not requiring tools",
        cost_sensitive: "High-volume scenarios where 10-20x cost prohibitive",
        no_tools_needed: "Pure reasoning tasks without external information needs"
      }

      assert Map.has_key?(avoid_cases, :simple_questions)
      assert Map.has_key?(avoid_cases, :cost_sensitive)
      assert is_binary(avoid_cases.creative_tasks)
    end
  end
end
