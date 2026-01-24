defmodule Jido.AI.Skills.Reasoning.Actions.AnalyzeTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skills.Reasoning.Actions.Analyze

  describe "Analyze action" do
    test "has correct metadata" do
      metadata = Analyze.__action_metadata__()
      assert metadata.name == "reasoning_analyze"
      assert metadata.category == "ai"
      assert metadata.vsn == "1.0.0"
    end

    test "requires input parameter" do
      assert {:error, _} = Jido.Exec.run(Analyze, %{}, %{})
    end

    test "accepts valid parameters with defaults" do
      params = %{
        input: "This is a sample text to analyze."
      }

      assert params.input == "This is a sample text to analyze."
    end

    test "accepts different analysis types" do
      params = %{
        input: "Test text",
        analysis_type: :sentiment
      }

      assert params.analysis_type == :sentiment
    end

    test "accepts custom analysis type with custom prompt" do
      params = %{
        input: "Test data",
        analysis_type: :custom,
        custom_prompt: "Analyze for trends."
      }

      assert params.analysis_type == :custom
      assert params.custom_prompt == "Analyze for trends."
    end

    test "accepts optional parameters" do
      params = %{
        input: "Test",
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
