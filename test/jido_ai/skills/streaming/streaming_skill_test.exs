defmodule Jido.AI.Skills.StreamingTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skills.Streaming

  describe "skill_spec/1" do
    test "returns valid skill spec with empty config" do
      spec = Streaming.skill_spec(%{})

      assert spec.module == Streaming
      assert spec.name == "streaming"
      assert spec.state_key == :streaming
      assert spec.category == "ai"
      assert is_list(spec.actions)
      assert length(spec.actions) == 3
    end

    test "includes config in skill spec" do
      config = %{default_model: :fast, default_buffer_size: 4096}
      spec = Streaming.skill_spec(config)

      assert spec.config == config
    end
  end

  describe "mount/2" do
    test "initializes state with defaults" do
      {:ok, state} = Streaming.mount(%Jido.Agent{}, %{})

      assert state.default_model == :fast
      assert state.default_max_tokens == 1024
      assert state.default_temperature == 0.7
      assert state.default_buffer_size == 8192
      assert is_map(state.active_streams)
    end

    test "merges custom config into initial state" do
      {:ok, state} =
        Streaming.mount(%Jido.Agent{}, %{default_model: :capable, default_max_tokens: 2048})

      assert state.default_model == :capable
      assert state.default_max_tokens == 2048
      assert state.default_temperature == 0.7
    end
  end

  describe "actions" do
    test "returns all three actions" do
      actions = Streaming.actions()

      assert length(actions) == 3
      assert Jido.AI.Skills.Streaming.Actions.StartStream in actions
      assert Jido.AI.Skills.Streaming.Actions.ProcessTokens in actions
      assert Jido.AI.Skills.Streaming.Actions.EndStream in actions
    end
  end
end
