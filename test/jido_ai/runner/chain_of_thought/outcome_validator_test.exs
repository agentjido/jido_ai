defmodule Jido.AI.Runner.ChainOfThought.OutcomeValidatorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.ChainOfThought.OutcomeValidator
  alias Jido.AI.Runner.ChainOfThought.OutcomeValidator.ValidationResult
  alias Jido.AI.Runner.ChainOfThought.ReasoningParser.ReasoningStep

  describe "validate/3" do
    test "successful result matches expectation" do
      step = %ReasoningStep{
        number: 1,
        description: "Process data",
        expected_outcome: "Data processed successfully"
      }

      result = {:ok, %{status: :processed}}

      validation = OutcomeValidator.validate(result, step, log_discrepancies: false)

      assert validation.matches_expectation == true
      assert validation.confidence == 1.0
    end

    test "error result does not match expectation" do
      step = %ReasoningStep{
        number: 1,
        description: "Process data",
        expected_outcome: "Data processed"
      }

      result = {:error, "Invalid data"}

      validation = OutcomeValidator.validate(result, step, log_discrepancies: false)

      assert validation.matches_expectation == false
      assert validation.confidence == 0.0
    end

    test "includes expected and actual outcomes" do
      step = %ReasoningStep{
        number: 1,
        description: "Test",
        expected_outcome: "Success expected"
      }

      result = {:ok, %{data: "value"}}

      validation = OutcomeValidator.validate(result, step, log_discrepancies: false)

      assert validation.expected_outcome == "Success expected"
      assert validation.actual_outcome =~ "data"
    end

    test "handles step without expected outcome" do
      step = %ReasoningStep{
        number: 1,
        description: "Test",
        expected_outcome: ""
      }

      result = {:ok, %{}}

      validation = OutcomeValidator.validate(result, step, log_discrepancies: false)

      assert validation.matches_expectation == true
      assert validation.expected_outcome == ""
      assert Enum.any?(validation.notes, &String.contains?(&1, "No expected outcome"))
    end

    test "includes notes for validation failures" do
      step = %ReasoningStep{
        number: 1,
        description: "Test",
        expected_outcome: "Should succeed"
      }

      result = {:error, "Failed"}

      validation = OutcomeValidator.validate(result, step, log_discrepancies: false)

      assert length(validation.notes) > 0
      assert Enum.any?(validation.notes, &String.contains?(&1, "Execution failed"))
    end
  end

  describe "successful?/1" do
    test "recognizes ok tuples as successful" do
      assert OutcomeValidator.successful?({:ok, %{}}) == true
      assert OutcomeValidator.successful?({:ok, "result"}) == true
      assert OutcomeValidator.successful?(:ok) == true
    end

    test "recognizes error tuples as not successful" do
      assert OutcomeValidator.successful?({:error, "reason"}) == false
      assert OutcomeValidator.successful?(:error) == false
    end

    test "recognizes boolean results" do
      assert OutcomeValidator.successful?(true) == true
      assert OutcomeValidator.successful?(false) == false
    end

    test "treats unknown results as successful" do
      assert OutcomeValidator.successful?("some value") == true
      assert OutcomeValidator.successful?(%{}) == true
      assert OutcomeValidator.successful?(123) == true
    end
  end

  describe "unexpected_outcome?/1" do
    test "identifies validation failures as unexpected" do
      validation = %ValidationResult{
        matches_expectation: false,
        expected_outcome: "Success",
        actual_outcome: "Error",
        confidence: 0.0
      }

      assert OutcomeValidator.unexpected_outcome?(validation) == true
    end

    test "identifies low confidence as unexpected" do
      validation = %ValidationResult{
        matches_expectation: true,
        confidence: 0.3
      }

      assert OutcomeValidator.unexpected_outcome?(validation) == true
    end

    test "normal successful validation is not unexpected" do
      validation = %ValidationResult{
        matches_expectation: true,
        confidence: 1.0
      }

      assert OutcomeValidator.unexpected_outcome?(validation) == false
    end

    test "moderate confidence is not unexpected if matches" do
      validation = %ValidationResult{
        matches_expectation: true,
        confidence: 0.8
      }

      assert OutcomeValidator.unexpected_outcome?(validation) == false
    end
  end

  describe "ValidationResult struct" do
    test "has default values" do
      result = %ValidationResult{}

      assert result.matches_expectation == true
      assert result.expected_outcome == nil
      assert result.actual_outcome == nil
      assert result.confidence == 1.0
      assert result.notes == []
    end
  end

  describe "validation with different result types" do
    setup do
      step = %ReasoningStep{
        number: 1,
        description: "Test step",
        expected_outcome: "Expected result"
      }

      {:ok, step: step}
    end

    test "validates map results", %{step: step} do
      result = %{status: :success, data: "value"}
      validation = OutcomeValidator.validate(result, step, log_discrepancies: false)

      assert validation.matches_expectation == true
    end

    test "validates string results", %{step: step} do
      result = "operation completed"
      validation = OutcomeValidator.validate(result, step, log_discrepancies: false)

      assert validation.matches_expectation == true
    end

    test "validates integer results", %{step: step} do
      result = 42
      validation = OutcomeValidator.validate(result, step, log_discrepancies: false)

      assert validation.matches_expectation == true
    end
  end

  describe "validation logging" do
    test "can disable logging" do
      step = %ReasoningStep{
        number: 1,
        description: "Test",
        expected_outcome: "Success"
      }

      result = {:error, "Failed"}

      # Should not raise or cause issues
      validation = OutcomeValidator.validate(result, step, log_discrepancies: false)

      assert validation.matches_expectation == false
    end

    test "logging enabled by default for failures" do
      step = %ReasoningStep{
        number: 1,
        description: "Test",
        expected_outcome: "Success"
      }

      result = {:error, "Failed"}

      # Should log but not raise
      validation = OutcomeValidator.validate(result, step)

      assert validation.matches_expectation == false
    end
  end
end
