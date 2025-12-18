defmodule Jido.AI.Runner.ChainOfThought.TaskSpecificZeroShotTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.ChainOfThought.TaskSpecificZeroShot

  describe "generate/1" do
    @tag :skip
    test "generates mathematical reasoning" do
      {:ok, reasoning} =
        TaskSpecificZeroShot.generate(
          problem: "Calculate 15% of 240",
          task_type: :mathematical
        )

      assert reasoning.problem == "Calculate 15% of 240"
      assert reasoning.task_type == :mathematical
      assert is_list(reasoning.steps)
      assert is_map(reasoning.task_specific)
    end

    test "returns error when problem is missing" do
      assert {:error, "Problem is required"} =
               TaskSpecificZeroShot.generate(task_type: :mathematical)
    end

    test "returns error when problem is empty string" do
      assert {:error, "Problem must be a non-empty string"} =
               TaskSpecificZeroShot.generate(problem: "", task_type: :mathematical)
    end

    test "returns error when task_type is missing" do
      assert {:error, "Task type is required"} =
               TaskSpecificZeroShot.generate(problem: "test")
    end

    test "returns error when task_type is invalid" do
      assert {:error, "Invalid task type: invalid"} =
               TaskSpecificZeroShot.generate(problem: "test", task_type: :invalid)
    end
  end

  describe "build_task_specific_prompt/3" do
    test "builds mathematical reasoning prompt" do
      {:ok, prompt} =
        TaskSpecificZeroShot.build_task_specific_prompt("Calculate 2+2", :mathematical, [])

      content = hd(prompt.messages).content

      assert content =~ "Mathematical Reasoning"
      assert content =~ "Calculate 2+2"
      assert content =~ "step by step"
      assert content =~ "calculations"
    end

    test "builds debugging prompt" do
      {:ok, prompt} =
        TaskSpecificZeroShot.build_task_specific_prompt("Fix this error", :debugging, [])

      content = hd(prompt.messages).content

      assert content =~ "Debugging"
      assert content =~ "Fix this error"
      assert content =~ "error message"
      assert content =~ "root cause"
    end

    test "builds workflow prompt" do
      {:ok, prompt} =
        TaskSpecificZeroShot.build_task_specific_prompt("Process signup", :workflow, [])

      content = hd(prompt.messages).content

      assert content =~ "Workflow"
      assert content =~ "Process signup"
      assert content =~ "dependencies"
      assert content =~ "steps"
    end

    test "includes context when provided" do
      {:ok, prompt} =
        TaskSpecificZeroShot.build_task_specific_prompt("Test", :mathematical,
          context: %{unit: "meters"}
        )

      content = hd(prompt.messages).content
      assert content =~ "Context:"
      assert content =~ "unit"
    end

    test "omits context when empty" do
      {:ok, prompt} =
        TaskSpecificZeroShot.build_task_specific_prompt("Test", :mathematical, context: %{})

      content = hd(prompt.messages).content
      refute content =~ "Context:"
    end

    test "returns Jido.AI.Prompt struct" do
      {:ok, prompt} =
        TaskSpecificZeroShot.build_task_specific_prompt("Test", :mathematical, [])

      assert %Jido.AI.Prompt{} = prompt
      message = hd(prompt.messages)
      assert message.role == :user
    end
  end

  describe "parse_task_specific_reasoning/3 - mathematical" do
    test "parses mathematical reasoning with calculations" do
      response = """
      Let's solve this step by step:

      1. First, convert 15% to decimal: 15/100 = 0.15
      2. Multiply by 240: 0.15 × 240 = 36
      3. Verification: 36/240 = 0.15 = 15%

      Therefore, the answer is 36.
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(
          response,
          "Calculate 15% of 240",
          :mathematical
        )

      assert reasoning.problem == "Calculate 15% of 240"
      assert reasoning.task_type == :mathematical
      assert length(reasoning.steps) >= 3
      assert reasoning.answer == "36"
      assert is_map(reasoning.task_specific)
      assert is_list(reasoning.task_specific.calculations)
      assert is_list(reasoning.task_specific.intermediate_results)
    end

    test "extracts calculations from mathematical reasoning" do
      response = """
      1. Calculate area: A = π × r²
      2. Substitute: A = 3.14 × 5²
      3. Compute: A = 3.14 × 25 = 78.5

      The area is 78.5 square units.
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :mathematical)

      calcs = reasoning.task_specific.calculations

      assert length(calcs) >= 2
      assert Enum.any?(calcs, &(&1 =~ "="))
    end

    test "extracts intermediate results" do
      response = """
      Step 1: 5 × 3 = 15
      Step 2: 15 + 7 = 22
      Step 3: 22 / 2 = 11
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :mathematical)

      results = reasoning.task_specific.intermediate_results

      assert "15" in results
      assert "22" in results
      assert "11" in results
    end

    test "extracts verification when present" do
      response = """
      Result: 42
      Verification: 42 × 2 = 84 (correct)
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :mathematical)

      assert reasoning.task_specific.verification =~ "42"
    end
  end

  describe "parse_task_specific_reasoning/3 - debugging" do
    test "parses debugging reasoning with error analysis" do
      response = """
      Let's debug this step by step:

      1. Error: FunctionClauseError in foo/1
      2. Root cause: Missing pattern match for empty list
      3. Fix: Add clause `def foo([]), do: []`

      The fix addresses the root cause by handling the empty list case.
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(
          response,
          "Fix function error",
          :debugging
        )

      assert reasoning.problem == "Fix function error"
      assert reasoning.task_type == :debugging
      assert length(reasoning.steps) >= 3
      assert is_map(reasoning.task_specific)

      assert is_binary(reasoning.task_specific.error_analysis) or
               is_nil(reasoning.task_specific.error_analysis)
    end

    test "extracts error analysis" do
      response = """
      Error: undefined function bar/0
      The error occurs because...
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :debugging)

      assert reasoning.task_specific.error_analysis =~ "undefined function"
    end

    test "extracts root cause" do
      response = """
      The problem happens here.
      Root cause: Missing import statement
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :debugging)

      assert reasoning.task_specific.root_cause =~ "Missing import"
    end

    test "extracts proposed fix" do
      response = """
      To resolve this issue...
      Fix: Add `import Foo` at the top
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :debugging)

      assert reasoning.task_specific.proposed_fix =~ "Add `import Foo`"
    end
  end

  describe "parse_task_specific_reasoning/3 - workflow" do
    test "parses workflow reasoning with actions" do
      response = """
      Workflow steps:

      1. Validate user input
      2. Create user record in database
      3. Send verification email
      4. Return success response

      Dependencies: Step 3 depends on step 2
      Error handling: If email fails, mark user as unverified
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(
          response,
          "User signup flow",
          :workflow
        )

      assert reasoning.problem == "User signup flow"
      assert reasoning.task_type == :workflow
      assert length(reasoning.steps) >= 4
      assert is_map(reasoning.task_specific)
      assert is_list(reasoning.task_specific.actions)
      assert length(reasoning.task_specific.actions) >= 4
    end

    test "extracts actions from workflow" do
      response = """
      1. Fetch data from API
      2. Transform data
      3. Save to database
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :workflow)

      actions = reasoning.task_specific.actions

      assert "Fetch data from API" in actions
      assert "Transform data" in actions
      assert "Save to database" in actions
    end

    test "extracts dependencies" do
      response = """
      Step 2 depends on: Step 1 completion
      Step 3 requires: Valid auth token
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :workflow)

      deps = reasoning.task_specific.dependencies

      assert length(deps) >= 1
      assert Enum.any?(deps, &(&1 =~ "Step 1" or &1 =~ "auth token"))
    end

    test "extracts error handling" do
      response = """
      If validation fails: return error
      On error: rollback transaction
      Fallback: use cached data
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :workflow)

      error_handling = reasoning.task_specific.error_handling

      assert length(error_handling) >= 1
    end
  end

  describe "custom task types" do
    test "registers custom task type" do
      :ok =
        TaskSpecificZeroShot.register_task_type(:optimization, %{
          guidance: "Focus on performance optimization"
        })

      {:ok, config} = TaskSpecificZeroShot.get_task_type_config(:optimization)
      assert config.guidance =~ "performance"
    end

    test "gets custom task type config" do
      TaskSpecificZeroShot.register_task_type(:testing, %{
        guidance: "Write comprehensive tests"
      })

      {:ok, config} = TaskSpecificZeroShot.get_task_type_config(:testing)
      assert config.guidance =~ "tests"
    end

    test "returns error for non-existent task type" do
      assert {:error, :not_found} =
               TaskSpecificZeroShot.get_task_type_config(:nonexistent)
    end

    test "lists custom task types" do
      TaskSpecificZeroShot.register_task_type(:custom1, %{guidance: "Test 1"})
      TaskSpecificZeroShot.register_task_type(:custom2, %{guidance: "Test 2"})

      custom_types = TaskSpecificZeroShot.list_custom_task_types()

      assert :custom1 in custom_types
      assert :custom2 in custom_types
    end

    test "builds prompt for custom task type" do
      TaskSpecificZeroShot.register_task_type(:analysis, %{
        guidance: "Analyze the data thoroughly"
      })

      {:ok, prompt} =
        TaskSpecificZeroShot.build_task_specific_prompt("Analyze metrics", :analysis, [])

      content = hd(prompt.messages).content

      assert content =~ "Analysis"
      assert content =~ "Analyze the data thoroughly"
    end

    test "accepts custom task type in generate" do
      TaskSpecificZeroShot.register_task_type(:review, %{
        guidance: "Review code quality"
      })

      # This would normally call LLM, but we're just checking validation
      # The actual LLM call is skipped in tests
      problem = "Review this function"
      task_type = :review

      {:ok, prompt} =
        TaskSpecificZeroShot.build_task_specific_prompt(problem, task_type, [])

      assert %Jido.AI.Prompt{} = prompt
    end
  end

  describe "step extraction" do
    test "extracts numbered steps" do
      response = """
      1. First step
      2. Second step
      3. Third step
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :mathematical)

      assert length(reasoning.steps) == 3
      assert "First step" in reasoning.steps
      assert "Second step" in reasoning.steps
      assert "Third step" in reasoning.steps
    end

    test "extracts Step N: format" do
      response = """
      Step 1: Initialize variables
      Step 2: Process data
      Step 3: Return result
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :workflow)

      assert length(reasoning.steps) == 3
      assert "Initialize variables" in reasoning.steps
    end

    test "extracts bullet points" do
      response = """
      - Validate input
      - Transform data
      - Save result
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :workflow)

      assert length(reasoning.steps) == 3
      assert "Validate input" in reasoning.steps
    end

    test "extracts First, Then, Finally format" do
      response = """
      First, check the input
      Then, process the data
      Finally, return the result
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :workflow)

      assert length(reasoning.steps) >= 3
    end

    test "filters out very short lines" do
      response = """
      1. Valid step here
      2. OK
      3. Another valid step
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :mathematical)

      assert "Valid step here" in reasoning.steps
      assert "Another valid step" in reasoning.steps
      refute "OK" in reasoning.steps
    end
  end

  describe "answer extraction" do
    test "extracts answer with Therefore prefix" do
      response = """
      Step 1: Calculate
      Therefore, the answer is 42.
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :mathematical)

      assert reasoning.answer == "42"
    end

    test "extracts answer with So prefix" do
      response = """
      Step 1: Process
      So the answer is: complete.
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :workflow)

      assert reasoning.answer == "complete"
    end

    test "extracts answer with 'The answer is'" do
      response = """
      After calculation...
      The answer is 100.
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :mathematical)

      assert reasoning.answer == "100"
    end

    test "falls back to last step if no explicit answer" do
      response = """
      1. First step
      2. Second step
      3. Final step result
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :workflow)

      assert reasoning.answer == "Final step result"
    end
  end

  describe "includes timestamp" do
    test "adds timestamp to reasoning" do
      response = "1. Test step"

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(response, "Test", :mathematical)

      assert %DateTime{} = reasoning.timestamp
    end
  end

  describe "integration" do
    test "complete mathematical workflow without LLM" do
      problem = "Calculate the circumference of a circle with radius 7"

      {:ok, prompt} =
        TaskSpecificZeroShot.build_task_specific_prompt(problem, :mathematical, [])

      assert %Jido.AI.Prompt{} = prompt

      mock_response = """
      Let's solve this step by step:

      1. Use formula: C = 2πr
      2. Substitute r = 7: C = 2π(7)
      3. Calculate: C = 2 × 3.14 × 7 = 43.96

      Therefore, the answer is 43.96 units.
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(mock_response, problem, :mathematical)

      assert reasoning.problem == problem
      assert reasoning.task_type == :mathematical
      assert length(reasoning.steps) >= 3
      assert reasoning.answer == "43.96 units"
      assert length(reasoning.task_specific.calculations) >= 1
      assert length(reasoning.task_specific.intermediate_results) >= 1
    end

    test "complete debugging workflow without LLM" do
      problem = "Fix undefined function error"

      {:ok, prompt} = TaskSpecificZeroShot.build_task_specific_prompt(problem, :debugging, [])

      assert %Jido.AI.Prompt{} = prompt

      mock_response = """
      Let's debug this systematically:

      1. Error: undefined function process/1
      2. Root cause: Function is defined as process/2 but called with 1 arg
      3. Fix: Either add process/1 clause or update call site

      The error occurs because of arity mismatch.
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(mock_response, problem, :debugging)

      assert reasoning.problem == problem
      assert reasoning.task_type == :debugging
      assert length(reasoning.steps) >= 3
      assert reasoning.task_specific.error_analysis =~ "undefined function"
      assert reasoning.task_specific.root_cause =~ "arity mismatch"
    end

    test "complete workflow workflow without LLM" do
      problem = "Process payment with retry logic"

      {:ok, prompt} = TaskSpecificZeroShot.build_task_specific_prompt(problem, :workflow, [])

      assert %Jido.AI.Prompt{} = prompt

      mock_response = """
      Workflow for payment processing:

      1. Validate payment details
      2. Attempt payment with provider
      3. If fails, retry up to 3 times
      4. If still fails, notify user
      5. If succeeds, update order status

      Step 3 depends on: Step 2 failure
      On error: Log failure and send notification
      """

      {:ok, reasoning} =
        TaskSpecificZeroShot.parse_task_specific_reasoning(mock_response, problem, :workflow)

      assert reasoning.problem == problem
      assert reasoning.task_type == :workflow
      assert length(reasoning.steps) >= 5
      assert length(reasoning.task_specific.actions) >= 5
      assert length(reasoning.task_specific.dependencies) >= 1
      assert length(reasoning.task_specific.error_handling) >= 1
    end
  end
end
