defmodule Jido.AI.Skills.ReasoningTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skills.Reasoning

  describe "skill_spec/1" do
    test "returns valid skill specification" do
      spec = Reasoning.skill_spec(%{})

      assert spec.module == Jido.AI.Skills.Reasoning
      assert spec.name == "reasoning"
      assert spec.state_key == :reasoning
      assert spec.description == "Provides AI-powered analysis, inference, and explanation capabilities"
      assert spec.category == "ai"
      assert spec.vsn == "1.0.0"
      assert spec.tags == ["reasoning", "analysis", "inference", "explanation", "ai"]
    end

    test "includes all three actions" do
      spec = Reasoning.skill_spec(%{})

      assert Jido.AI.Skills.Reasoning.Actions.Analyze in spec.actions
      assert Jido.AI.Skills.Reasoning.Actions.Infer in spec.actions
      assert Jido.AI.Skills.Reasoning.Actions.Explain in spec.actions
    end
  end

  describe "mount/2" do
    test "initializes skill with defaults" do
      assert {:ok, state} = Reasoning.mount(nil, %{})
      assert state.default_model == :reasoning
      assert state.default_max_tokens == 2048
      assert state.default_temperature == 0.3
    end

    test "accepts custom configuration" do
      assert {:ok, state} = Reasoning.mount(nil, %{default_model: :capable, default_max_tokens: 4096})
      assert state.default_model == :capable
      assert state.default_max_tokens == 4096
      assert state.default_temperature == 0.3
    end
  end
end
