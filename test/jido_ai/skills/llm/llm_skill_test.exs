defmodule Jido.AI.Plugins.LLMTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Plugins.LLM

  describe "plugin_spec/1" do
    test "returns valid skill specification" do
      spec = LLM.plugin_spec(%{})

      assert spec.module == Jido.AI.Plugins.LLM
      assert spec.name == "llm"
      assert spec.state_key == :llm
      assert spec.description == "Provides LLM chat, completion, and embedding capabilities"
      assert spec.category == "ai"
      assert spec.vsn == "1.0.0"
      assert spec.tags == ["llm", "chat", "completion", "embeddings", "reqllm"]
    end

    test "includes all three actions" do
      spec = LLM.plugin_spec(%{})

      assert Jido.AI.Actions.LLM.Chat in spec.actions
      assert Jido.AI.Actions.LLM.Complete in spec.actions
      assert Jido.AI.Actions.LLM.Embed in spec.actions
    end
  end

  describe "mount/2" do
    test "initializes skill with defaults" do
      assert {:ok, state} = LLM.mount(nil, %{})
      assert state.default_model == :fast
      assert state.default_max_tokens == 1024
      assert state.default_temperature == 0.7
    end

    test "accepts custom configuration" do
      assert {:ok, state} = LLM.mount(nil, %{default_model: :capable, default_max_tokens: 2048})
      assert state.default_model == :capable
      assert state.default_max_tokens == 2048
      assert state.default_temperature == 0.7
    end
  end
end
