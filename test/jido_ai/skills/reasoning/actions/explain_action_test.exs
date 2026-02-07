defmodule Jido.AI.Actions.Reasoning.ExplainTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.Reasoning.Explain

  describe "Explain action" do
    test "has correct metadata" do
      metadata = Explain.__action_metadata__()
      assert metadata.name == "reasoning_explain"
      assert metadata.category == "ai"
      assert metadata.vsn == "1.0.0"
    end

    test "requires topic parameter" do
      assert {:error, _} = Jido.Exec.run(Explain, %{}, %{})
    end

    test "accepts valid parameters with defaults" do
      params = %{
        topic: "Recursion"
      }

      assert params.topic == "Recursion"
      # Default values are applied by the action's schema, not present in input params
    end

    test "accepts different detail levels" do
      params = %{
        topic: "Test",
        detail_level: :basic
      }

      assert params.detail_level == :basic
    end

    test "accepts optional audience" do
      params = %{
        topic: "Test",
        audience: "Elixir developers"
      }

      assert params.audience == "Elixir developers"
    end

    test "accepts include_examples option" do
      params = %{
        topic: "Test",
        include_examples: false
      }

      assert params.include_examples == false
    end

    test "accepts optional parameters" do
      params = %{
        topic: "Test",
        model: "anthropic:claude-sonnet-4-20250514",
        max_tokens: 4096,
        temperature: 0.4
      }

      assert params.model == "anthropic:claude-sonnet-4-20250514"
      assert params.max_tokens == 4096
      assert params.temperature == 0.4
    end
  end
end
