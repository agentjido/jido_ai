defmodule Jido.AI.Runner.ChainOfThought.ReasoningParserTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.ChainOfThought.ReasoningParser
  alias Jido.AI.Runner.ChainOfThought.ReasoningParser.ReasoningPlan
  alias Jido.AI.Runner.ChainOfThought.ReasoningParser.ReasoningStep

  doctest ReasoningParser

  describe "parse/1" do
    test "parses complete reasoning output" do
      text = """
      GOAL: Process user data and generate report

      ANALYSIS:
      The instructions require data validation followed by transformation.
      We need to ensure data integrity before processing.

      EXECUTION_PLAN:
      Step 1: Validate input data format [Data is well-formed]
      Step 2: Transform data to required schema [Data matches target schema]
      Step 3: Generate summary report [Report is complete]

      EXPECTED_RESULTS:
      A validated and transformed dataset with a complete summary report.

      POTENTIAL_ISSUES:
      - Invalid data format
      - Missing required fields
      - Transformation errors
      """

      assert {:ok, plan} = ReasoningParser.parse(text)
      assert %ReasoningPlan{} = plan
      assert plan.goal == "Process user data and generate report"
      assert plan.analysis =~ "data validation"
      assert length(plan.steps) == 3
      assert plan.expected_results =~ "validated and transformed"
      assert length(plan.potential_issues) == 3
    end

    test "parses steps with expected outcomes" do
      text = """
      EXECUTION_PLAN:
      Step 1: Initialize system [System is ready]
      Step 2: Load configuration (Config is loaded)
      """

      {:ok, plan} = ReasoningParser.parse(text)

      assert length(plan.steps) == 2
      assert [step1, step2] = plan.steps

      assert step1.number == 1
      assert step1.description =~ "Initialize system"
      assert step1.expected_outcome =~ "System is ready"

      assert step2.number == 2
      assert step2.description =~ "Load configuration"
      assert step2.expected_outcome =~ "Config is loaded"
    end

    test "handles missing sections gracefully" do
      text = """
      GOAL: Simple task

      EXECUTION_PLAN:
      Step 1: Do something
      """

      assert {:ok, plan} = ReasoningParser.parse(text)
      assert plan.goal == "Simple task"
      assert plan.analysis == ""
      assert length(plan.steps) == 1
      assert plan.expected_results == ""
      assert plan.potential_issues == []
    end

    test "returns error for invalid input" do
      assert {:error, _reason} = ReasoningParser.parse(nil)
      assert {:error, _reason} = ReasoningParser.parse(123)
      assert {:error, _reason} = ReasoningParser.parse(%{})
    end

    test "preserves raw text" do
      text = "GOAL: Test\n\nSome content"

      {:ok, plan} = ReasoningParser.parse(text)

      assert plan.raw_text == text
    end
  end

  describe "extract_section/2" do
    test "extracts simple section" do
      text = """
      GOAL: Main objective here

      ANALYSIS: Some analysis
      """

      assert ReasoningParser.extract_section(text, "GOAL") == "Main objective here"
      assert ReasoningParser.extract_section(text, "ANALYSIS") == "Some analysis"
    end

    test "handles multi-line sections" do
      text = """
      ANALYSIS:
      Line one
      Line two
      Line three

      GOAL: Something
      """

      analysis = ReasoningParser.extract_section(text, "ANALYSIS")
      assert analysis =~ "Line one"
      assert analysis =~ "Line two"
      assert analysis =~ "Line three"
    end

    test "returns empty string for missing section" do
      text = "GOAL: Test"

      assert ReasoningParser.extract_section(text, "ANALYSIS") == ""
      assert ReasoningParser.extract_section(text, "MISSING") == ""
    end

    test "handles sections at end of text" do
      text = """
      GOAL: Test

      EXPECTED_RESULTS:
      Final results here
      """

      assert ReasoningParser.extract_section(text, "EXPECTED_RESULTS") =~ "Final results"
    end
  end

  describe "extract_steps/1" do
    test "extracts numbered steps" do
      text = """
      EXECUTION_PLAN:
      Step 1: First action
      Step 2: Second action
      Step 3: Third action
      """

      steps = ReasoningParser.extract_steps(text)

      assert length(steps) == 3
      assert Enum.at(steps, 0).number == 1
      assert Enum.at(steps, 1).number == 2
      assert Enum.at(steps, 2).number == 3
    end

    test "extracts step descriptions" do
      text = """
      EXECUTION_PLAN:
      Step 1: Validate input data
      Step 2: Process the data
      """

      steps = ReasoningParser.extract_steps(text)

      assert Enum.at(steps, 0).description =~ "Validate input data"
      assert Enum.at(steps, 1).description =~ "Process the data"
    end

    test "extracts expected outcomes from brackets" do
      text = """
      EXECUTION_PLAN:
      Step 1: Load config [Config loaded successfully]
      Step 2: Initialize (System initialized)
      """

      steps = ReasoningParser.extract_steps(text)

      assert Enum.at(steps, 0).expected_outcome =~ "Config loaded"
      assert Enum.at(steps, 1).expected_outcome =~ "System initialized"
    end

    test "handles steps without expected outcomes" do
      text = """
      EXECUTION_PLAN:
      Step 1: Do something
      Step 2: Do another thing
      """

      steps = ReasoningParser.extract_steps(text)

      assert Enum.at(steps, 0).description =~ "Do something"
      assert Enum.at(steps, 0).expected_outcome == ""
    end

    test "returns empty list when no execution plan" do
      text = "GOAL: Test"

      assert ReasoningParser.extract_steps(text) == []
    end

    test "handles multi-line step descriptions" do
      text = """
      EXECUTION_PLAN:
      Step 1: First do this
      and then do that
      Step 2: Another action
      """

      steps = ReasoningParser.extract_steps(text)

      assert length(steps) == 2
      assert Enum.at(steps, 0).description =~ "First do this"
    end
  end

  describe "extract_issues/1" do
    test "extracts bullet point issues" do
      text = """
      POTENTIAL_ISSUES:
      - First issue
      - Second issue
      - Third issue
      """

      issues = ReasoningParser.extract_issues(text)

      assert length(issues) == 3
      assert "First issue" in issues
      assert "Second issue" in issues
      assert "Third issue" in issues
    end

    test "handles different bullet styles" do
      text = """
      POTENTIAL_ISSUES:
      • Issue with bullet
      * Issue with asterisk
      - Issue with dash
      """

      issues = ReasoningParser.extract_issues(text)

      assert length(issues) == 3
    end

    test "handles newline-separated issues" do
      text = """
      POTENTIAL_ISSUES:
      Issue one
      Issue two
      Issue three
      """

      issues = ReasoningParser.extract_issues(text)

      assert length(issues) >= 3
    end

    test "returns empty list when no issues section" do
      text = "GOAL: Test"

      assert ReasoningParser.extract_issues(text) == []
    end

    test "filters empty strings" do
      text = """
      POTENTIAL_ISSUES:
      - Valid issue

      - Another issue
      """

      issues = ReasoningParser.extract_issues(text)

      assert Enum.all?(issues, fn issue -> issue != "" end)
    end
  end

  describe "validate/1" do
    test "validates plan with all required components" do
      plan = %ReasoningPlan{
        goal: "Test goal",
        analysis: "Test analysis",
        steps: [
          %ReasoningStep{number: 1, description: "Step 1", expected_outcome: "Done"}
        ],
        expected_results: "Results",
        potential_issues: ["Issue 1"]
      }

      assert :ok = ReasoningParser.validate(plan)
    end

    test "rejects plan without goal" do
      plan = %ReasoningPlan{
        goal: "",
        steps: [%ReasoningStep{number: 1, description: "Step", expected_outcome: ""}]
      }

      assert {:error, reason} = ReasoningParser.validate(plan)
      assert reason =~ "missing goal"
    end

    test "rejects plan with nil goal" do
      plan = %ReasoningPlan{
        goal: nil,
        steps: [%ReasoningStep{number: 1, description: "Step", expected_outcome: ""}]
      }

      assert {:error, reason} = ReasoningParser.validate(plan)
      assert reason =~ "missing goal"
    end

    test "rejects plan without steps" do
      plan = %ReasoningPlan{
        goal: "Test",
        steps: []
      }

      assert {:error, reason} = ReasoningParser.validate(plan)
      assert reason =~ "no execution steps"
    end

    test "rejects plan with invalid steps" do
      plan = %ReasoningPlan{
        goal: "Test",
        steps: [
          %ReasoningStep{number: 1, description: "", expected_outcome: ""}
        ]
      }

      assert {:error, reason} = ReasoningParser.validate(plan)
      assert reason =~ "invalid steps"
    end

    test "accepts plan with minimal valid data" do
      plan = %ReasoningPlan{
        goal: "Minimal goal",
        analysis: "",
        steps: [
          %ReasoningStep{number: 1, description: "Do something", expected_outcome: ""}
        ],
        expected_results: "",
        potential_issues: []
      }

      assert :ok = ReasoningParser.validate(plan)
    end
  end
end
