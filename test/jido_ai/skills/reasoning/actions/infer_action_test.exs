defmodule Jido.AI.Skills.Reasoning.Actions.InferTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skills.Reasoning.Actions.Infer

  describe "Infer action" do
    test "has correct metadata" do
      metadata = Infer.__action_metadata__()
      assert metadata.name == "reasoning_infer"
      assert metadata.category == "ai"
      assert metadata.vsn == "1.0.0"
    end

    test "requires premises parameter" do
      assert {:error, _} = Jido.Exec.run(Infer, %{question: "Test"}, %{})
    end

    test "requires question parameter" do
      assert {:error, _} = Jido.Exec.run(Infer, %{premises: "Test"}, %{})
    end

    test "accepts valid parameters with defaults" do
      params = %{
        premises: "All cats are mammals.",
        question: "What are cats?"
      }

      assert params.premises == "All cats are mammals."
      assert params.question == "What are cats?"
    end

    test "accepts optional context" do
      params = %{
        premises: "Test premises",
        question: "Test question",
        context: "Additional background"
      }

      assert params.context == "Additional background"
    end

    test "accepts optional parameters" do
      params = %{
        premises: "Test",
        question: "Test",
        model: "anthropic:claude-sonnet-4-20250514",
        max_tokens: 4096,
        temperature: 0.2
      }

      assert params.model == "anthropic:claude-sonnet-4-20250514"
      assert params.max_tokens == 4096
      assert params.temperature == 0.2
    end
  end
end
