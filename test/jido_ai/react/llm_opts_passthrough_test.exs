defmodule Jido.AI.Reasoning.ReAct.LlmOptsPassthroughTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.ReAct.Config

  describe "Config.llm_opts/1 with llm_opts passthrough" do
    test "merges extra llm_opts into output" do
      config =
        Config.new(%{
          model: "anthropic:claude-sonnet-4-5",
          max_tokens: 1024,
          llm_opts: [web_search: %{max_uses: 5}]
        })

      opts = Config.llm_opts(config)

      assert Keyword.get(opts, :web_search) == %{max_uses: 5}
      assert Keyword.get(opts, :max_tokens) == 1024
    end

    test "empty llm_opts does not affect output" do
      config =
        Config.new(%{
          model: "anthropic:claude-sonnet-4-5",
          max_tokens: 2048,
          llm_opts: []
        })

      opts = Config.llm_opts(config)

      assert Keyword.get(opts, :max_tokens) == 2048
      refute Keyword.has_key?(opts, :web_search)
    end

    test "llm_opts defaults to empty list" do
      config =
        Config.new(%{
          model: "anthropic:claude-sonnet-4-5"
        })

      opts = Config.llm_opts(config)

      assert Keyword.get(opts, :max_tokens) == 1024
      refute Keyword.has_key?(opts, :web_search)
    end

    test "llm_opts supports provider-specific options like thinking" do
      config =
        Config.new(%{
          model: "anthropic:claude-sonnet-4-5",
          llm_opts: [thinking: %{type: "enabled", budget_tokens: 4096}]
        })

      opts = Config.llm_opts(config)

      assert Keyword.get(opts, :thinking) == %{type: "enabled", budget_tokens: 4096}
    end

    test "llm_opts can override base options" do
      config =
        Config.new(%{
          model: "anthropic:claude-sonnet-4-5",
          temperature: 0.2,
          llm_opts: [temperature: 0.8]
        })

      opts = Config.llm_opts(config)

      # llm_opts merges after base, so it overrides
      assert Keyword.get(opts, :temperature) == 0.8
    end

    test "multiple provider options can be passed" do
      config =
        Config.new(%{
          model: "anthropic:claude-sonnet-4-5",
          llm_opts: [
            web_search: %{max_uses: 3},
            anthropic_prompt_cache: true
          ]
        })

      opts = Config.llm_opts(config)

      assert Keyword.get(opts, :web_search) == %{max_uses: 3}
      assert Keyword.get(opts, :anthropic_prompt_cache) == true
    end
  end
end
