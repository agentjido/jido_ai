defmodule Jido.AI.GEPA.TaskTest do
  use ExUnit.Case, async: true

  alias Jido.AI.GEPA.Task

  # ============================================================================
  # Struct Creation - new/1
  # ============================================================================

  describe "new/1" do
    test "creates task with input and expected" do
      assert {:ok, task} = Task.new(%{input: "What is 2+2?", expected: "4"})

      assert task.input == "What is 2+2?"
      assert task.expected == "4"
      assert task.validator == nil
      assert task.metadata == %{}
      assert String.starts_with?(task.id, "task_")
    end

    test "creates task with input and validator" do
      validator = fn output -> String.contains?(output, "4") end
      assert {:ok, task} = Task.new(%{input: "What is 2+2?", validator: validator})

      assert task.input == "What is 2+2?"
      assert task.expected == nil
      assert is_function(task.validator, 1)
    end

    test "creates task with input only" do
      assert {:ok, task} = Task.new(%{input: "Explain recursion"})

      assert task.input == "Explain recursion"
      assert task.expected == nil
      assert task.validator == nil
    end

    test "uses provided id" do
      assert {:ok, task} = Task.new(%{input: "test", id: "custom-task-id"})
      assert task.id == "custom-task-id"
    end

    test "uses provided metadata" do
      metadata = %{category: "math", difficulty: "easy"}
      assert {:ok, task} = Task.new(%{input: "2+2?", metadata: metadata})
      assert task.metadata == metadata
    end

    test "returns error when input is missing" do
      assert {:error, :input_required} = Task.new(%{})
    end

    test "returns error when input is not a string" do
      assert {:error, :invalid_input} = Task.new(%{input: 123})
      assert {:error, :invalid_input} = Task.new(%{input: nil})
    end

    test "returns error when input is empty string" do
      assert {:error, :empty_input} = Task.new(%{input: ""})
      assert {:error, :empty_input} = Task.new(%{input: "   "})
    end

    test "returns error when attrs is not a map" do
      assert {:error, :invalid_attrs} = Task.new("not a map")
      assert {:error, :invalid_attrs} = Task.new(nil)
    end
  end

  # ============================================================================
  # Struct Creation - new!/1
  # ============================================================================

  describe "new!/1" do
    test "creates task on success" do
      task = Task.new!(%{input: "What is 2+2?", expected: "4"})
      assert task.input == "What is 2+2?"
    end

    test "raises ArgumentError on missing input" do
      assert_raise ArgumentError, "input is required", fn ->
        Task.new!(%{})
      end
    end

    test "raises ArgumentError on invalid input" do
      assert_raise ArgumentError, "input must be a string", fn ->
        Task.new!(%{input: 123})
      end
    end

    test "raises ArgumentError on empty input" do
      assert_raise ArgumentError, "input cannot be empty", fn ->
        Task.new!(%{input: ""})
      end
    end
  end

  # ============================================================================
  # Success Checking
  # ============================================================================

  describe "success?/2 with validator" do
    test "returns true when validator passes" do
      task =
        Task.new!(%{
          input: "What is 2+2?",
          validator: fn output -> String.contains?(output, "4") end
        })

      assert Task.success?(task, "The answer is 4")
      assert Task.success?(task, "4")
    end

    test "returns false when validator fails" do
      task =
        Task.new!(%{
          input: "What is 2+2?",
          validator: fn output -> String.contains?(output, "4") end
        })

      refute Task.success?(task, "The answer is five")
      refute Task.success?(task, "I don't know")
    end

    test "returns false when validator raises" do
      task =
        Task.new!(%{
          input: "test",
          validator: fn _output -> raise "oops" end
        })

      refute Task.success?(task, "any output")
    end

    test "returns false when validator returns non-boolean truthy value" do
      task =
        Task.new!(%{
          input: "test",
          validator: fn _output -> "truthy" end
        })

      refute Task.success?(task, "output")
    end
  end

  describe "success?/2 with expected" do
    test "returns true when output contains expected" do
      task = Task.new!(%{input: "What is 2+2?", expected: "4"})

      assert Task.success?(task, "The answer is 4")
      assert Task.success?(task, "4")
      assert Task.success?(task, "I think it's 4, maybe")
    end

    test "returns true when output matches expected exactly" do
      task = Task.new!(%{input: "What is 2+2?", expected: "four"})

      assert Task.success?(task, "four")
      assert Task.success?(task, "FOUR")
      assert Task.success?(task, "  four  ")
    end

    test "is case insensitive" do
      task = Task.new!(%{input: "Capital?", expected: "Paris"})

      assert Task.success?(task, "paris")
      assert Task.success?(task, "PARIS")
      assert Task.success?(task, "The capital is Paris")
    end

    test "normalizes whitespace" do
      task = Task.new!(%{input: "test", expected: "hello world"})

      assert Task.success?(task, "hello  world")
      assert Task.success?(task, "hello\nworld")
      assert Task.success?(task, "  hello   world  ")
    end

    test "returns false when expected not found" do
      task = Task.new!(%{input: "What is 2+2?", expected: "4"})

      refute Task.success?(task, "five")
      refute Task.success?(task, "I don't know")
    end
  end

  describe "success?/2 with no criteria" do
    test "always returns true when no expected or validator" do
      task = Task.new!(%{input: "Explain something"})

      assert Task.success?(task, "any response")
      assert Task.success?(task, "")
      assert Task.success?(task, "anything goes")
    end
  end

  describe "success?/2 with nil output" do
    test "returns false when expected but output is nil" do
      task = Task.new!(%{input: "test", expected: "something"})

      # nil output should not match expected string
      refute Task.success?(task, nil)
    end

    test "returns true when no criteria and output is nil" do
      task = Task.new!(%{input: "test"})

      # No criteria means always passes
      assert Task.success?(task, nil)
    end

    test "handles nil output with validator" do
      task =
        Task.new!(%{
          input: "test",
          validator: fn output -> output == nil end
        })

      assert Task.success?(task, nil)
    end
  end

  # ============================================================================
  # Convenience Functions
  # ============================================================================

  describe "from_input/1" do
    test "creates task from input string" do
      task = Task.from_input("Explain recursion")

      assert task.input == "Explain recursion"
      assert task.expected == nil
      assert task.validator == nil
    end
  end

  describe "from_pairs/1" do
    test "creates tasks from input-expected pairs" do
      pairs = [
        {"What is 2+2?", "4"},
        {"What is 3+3?", "6"},
        {"What is 5+5?", "10"}
      ]

      tasks = Task.from_pairs(pairs)

      assert length(tasks) == 3
      assert Enum.at(tasks, 0).input == "What is 2+2?"
      assert Enum.at(tasks, 0).expected == "4"
      assert Enum.at(tasks, 1).input == "What is 3+3?"
      assert Enum.at(tasks, 1).expected == "6"
      assert Enum.at(tasks, 2).input == "What is 5+5?"
      assert Enum.at(tasks, 2).expected == "10"
    end

    test "returns empty list for empty input" do
      assert Task.from_pairs([]) == []
    end
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  describe "edge cases" do
    test "handles very long input strings" do
      long_input = String.duplicate("a", 100_000)
      {:ok, task} = Task.new(%{input: long_input})
      assert String.length(task.input) == 100_000
    end

    test "handles unicode in input and expected" do
      {:ok, task} =
        Task.new(%{
          input: "What is 2+2 in Japanese?",
          expected: "四"
        })

      assert Task.success?(task, "The answer is 四")
    end

    test "validator takes precedence over expected" do
      # When both validator and expected are set, validator is used
      task =
        Task.new!(%{
          input: "test",
          expected: "4",
          validator: fn output -> output == "five" end
        })

      # Validator says "five" is correct, not "4"
      assert Task.success?(task, "five")
      refute Task.success?(task, "4")
    end

    test "handles complex metadata" do
      metadata = %{
        category: "math",
        difficulty: "hard",
        tags: ["arithmetic", "basic"],
        nested: %{key: "value"}
      }

      {:ok, task} = Task.new(%{input: "test", metadata: metadata})
      assert task.metadata == metadata
    end
  end
end
