defmodule Jido.AI.Runner.ChainOfThought.ReasoningPromptTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Prompt
  alias Jido.AI.Runner.ChainOfThought.ReasoningPrompt

  doctest ReasoningPrompt

  # Helper to extract content from prompt
  defp get_content(%Prompt{messages: [message | _]}), do: message.content
  defp get_content(_), do: ""

  describe "zero_shot/3" do
    test "generates a prompt with instructions" do
      instructions = [
        %{action: TestAction, params: %{value: 42}},
        %{action: AnotherAction, params: %{data: "test"}}
      ]

      state = %{context: "test context"}

      prompt = ReasoningPrompt.zero_shot(instructions, state)

      assert %Prompt{} = prompt
      content = get_content(prompt)
      assert content =~ "Let's think step by step"
      assert content =~ "Pending Instructions (2 total)"
      assert content =~ "TestAction"
      assert content =~ "AnotherAction"
    end

    test "includes agent state in prompt" do
      instructions = [%{action: TestAction, params: %{value: 1}}]
      state = %{user_id: 123, context: "important"}

      prompt = ReasoningPrompt.zero_shot(instructions, state)
      content = get_content(prompt)

      assert content =~ "Current Agent State"
      assert content =~ "user_id"
      assert content =~ "context"
    end

    test "handles empty instructions" do
      instructions = []
      state = %{}

      prompt = ReasoningPrompt.zero_shot(instructions, state)

      assert %Prompt{} = prompt
      content = get_content(prompt)
      assert content =~ "Pending Instructions (0 total)"
      assert content =~ "(No instructions)"
    end

    test "formats expected output structure" do
      instructions = [%{action: TestAction, params: %{}}]
      state = %{}

      prompt = ReasoningPrompt.zero_shot(instructions, state)
      content = get_content(prompt)

      assert content =~ "GOAL:"
      assert content =~ "ANALYSIS:"
      assert content =~ "EXECUTION_PLAN:"
      assert content =~ "EXPECTED_RESULTS:"
      assert content =~ "POTENTIAL_ISSUES:"
    end

    test "truncates long parameter values" do
      long_value = String.duplicate("x", 200)
      instructions = [%{action: TestAction, params: %{data: long_value}}]

      prompt = ReasoningPrompt.zero_shot(instructions, %{})
      content = get_content(prompt)

      # Should truncate to 100 characters in params
      refute content =~ long_value
    end
  end

  describe "structured/3" do
    test "generates structured reasoning prompt" do
      instructions = [%{action: CodeAction, params: %{code: "def foo, do: :bar"}}]
      state = %{}

      prompt = ReasoningPrompt.structured(instructions, state)

      assert %Prompt{} = prompt
      content = get_content(prompt)
      assert content =~ "UNDERSTAND:"
      assert content =~ "PLAN:"
      assert content =~ "SEQUENCE:"
      assert content =~ "BRANCH:"
      assert content =~ "LOOP:"
      assert content =~ "FUNCTIONAL PATTERNS:"
      assert content =~ "IMPLEMENT:"
      assert content =~ "VALIDATE:"
    end

    test "includes data structures and constraints guidance" do
      instructions = [%{action: TestAction, params: %{}}]
      state = %{}

      prompt = ReasoningPrompt.structured(instructions, state)
      content = get_content(prompt)

      assert content =~ "data structures"
      assert content =~ "constraints"
      assert content =~ "edge cases"
    end
  end

  describe "few_shot/3" do
    test "currently delegates to zero_shot" do
      instructions = [%{action: TestAction, params: %{}}]
      state = %{}

      prompt = ReasoningPrompt.few_shot(instructions, state)

      assert %Prompt{} = prompt
      content = get_content(prompt)
      # Currently same as zero_shot
      assert content =~ "Let's think step by step"
    end
  end

  describe "format_instructions/1" do
    test "formats single instruction" do
      instructions = [%{action: MyModule.TestAction, params: %{value: 42}}]

      prompt = ReasoningPrompt.zero_shot(instructions, %{})
      content = get_content(prompt)

      assert content =~ "1. TestAction (value: 42)"
    end

    test "formats multiple instructions with numbering" do
      instructions = [
        %{action: FirstAction, params: %{}},
        %{action: SecondAction, params: %{}},
        %{action: ThirdAction, params: %{}}
      ]

      prompt = ReasoningPrompt.zero_shot(instructions, %{})
      content = get_content(prompt)

      assert content =~ "1. FirstAction"
      assert content =~ "2. SecondAction"
      assert content =~ "3. ThirdAction"
    end

    test "handles instructions with string action names" do
      instructions = [%{"action" => "CustomAction", "params" => %{}}]

      prompt = ReasoningPrompt.zero_shot(instructions, %{})
      content = get_content(prompt)

      assert content =~ "CustomAction"
    end

    test "handles instructions without params" do
      instructions = [%{action: TestAction}]

      prompt = ReasoningPrompt.zero_shot(instructions, %{})
      content = get_content(prompt)

      assert content =~ "TestAction"
      refute content =~ "TestAction ("
    end

    test "handles instructions with empty params" do
      instructions = [%{action: TestAction, params: %{}}]

      prompt = ReasoningPrompt.zero_shot(instructions, %{})
      content = get_content(prompt)

      assert content =~ "TestAction"
      refute content =~ "TestAction ("
    end
  end

  describe "format_state/1" do
    test "excludes internal state fields" do
      state = %{
        user_data: "visible",
        cot_config: "should be hidden"
      }

      prompt = ReasoningPrompt.zero_shot([], state)
      content = get_content(prompt)

      assert content =~ "user_data"
      refute content =~ "cot_config"
    end

    test "handles empty state" do
      prompt = ReasoningPrompt.zero_shot([], %{})
      content = get_content(prompt)

      refute content =~ "Current Agent State:"
    end

    test "truncates long state values" do
      long_value = String.duplicate("y", 300)
      state = %{data: long_value}

      prompt = ReasoningPrompt.zero_shot([], state)
      content = get_content(prompt)

      # Should truncate to 200 characters
      refute content =~ long_value
    end
  end
end
