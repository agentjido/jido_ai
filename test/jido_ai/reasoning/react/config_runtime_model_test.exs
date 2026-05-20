defmodule Jido.AI.Reasoning.ReAct.ConfigRuntimeModelTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.ReAct.Config

  describe "merge_llm_opts/4 with model override" do
    test "3-arg form validates provider_options against config.model" do
      config = Config.new(model: "openai:gpt-4.1")

      merged =
        Config.merge_llm_opts(
          config,
          [],
          provider_options: [verbosity: :medium]
        )

      assert get_in(merged, [:provider_options]) == [verbosity: :medium]
    end

    test "4-arg form validates provider_options against the override model" do
      # Boot config uses OpenAI; override to anthropic for this turn.
      config = Config.new(model: "openai:gpt-4.1")

      merged =
        Config.merge_llm_opts(
          config,
          [],
          [provider_options: [reasoning_token_budget: 8192]],
          "anthropic:claude-sonnet-4-5"
        )

      assert get_in(merged, [:provider_options]) == [reasoning_token_budget: 8192]
    end

    test "4-arg form with nil model_override falls back to config.model" do
      config = Config.new(model: "openai:gpt-4.1")

      merged =
        Config.merge_llm_opts(
          config,
          [],
          [provider_options: [verbosity: :medium]],
          nil
        )

      assert get_in(merged, [:provider_options]) == [verbosity: :medium]
    end

    test "nil overrides return base_opts unchanged for both 3- and 4-arg forms" do
      config = Config.new(model: "openai:gpt-4.1")
      base = [max_tokens: 1024]

      assert Config.merge_llm_opts(config, base, nil) == base
      assert Config.merge_llm_opts(config, base, nil, "anthropic:claude-sonnet-4-5") == base
    end
  end
end
