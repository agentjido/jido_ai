defmodule Jido.AI.CoreTest do
  use ExUnit.Case, async: false
  alias Jido.AI.Models

  setup do
    old_aliases = Application.get_env(:jido_ai, :model_aliases)

    on_exit(fn ->
      if is_nil(old_aliases) do
        Application.delete_env(:jido_ai, :model_aliases)
      else
        Application.put_env(:jido_ai, :model_aliases, old_aliases)
      end
    end)

    :ok
  end

  defp with_model_aliases(aliases, fun) do
    original = Application.get_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, aliases)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:jido_ai, :model_aliases)
      else
        Application.put_env(:jido_ai, :model_aliases, original)
      end
    end)

    fun.()
  end

  describe "model aliases" do
    test "aliases/0 merges application aliases over package configuration" do
      aliases =
        with_model_aliases(%{fast: "openai:gpt-4.1-mini", custom: "test:custom"}, fn ->
          Models.aliases()
        end)

      assert aliases[:fast] == "openai:gpt-4.1-mini"
      assert aliases[:custom] == "test:custom"
      assert is_binary(aliases[:capable])
    end

    test "aliases/0 supports direct model specs for configured aliases" do
      inline_model = %{provider: :openai, id: "gpt-4.1", base_url: "http://localhost:4000/v1"}

      aliases = with_model_aliases(%{capable: inline_model}, fn -> Models.aliases() end)
      assert aliases[:capable] == inline_model
    end

    test "resolve/1 passes strings, resolves aliases, and raises for unknown alias" do
      assert Models.resolve("openai:gpt-4.1") == "openai:gpt-4.1"
      assert is_binary(Models.resolve(:fast))

      assert_raise ArgumentError, ~r/Unknown model alias/, fn ->
        Models.resolve(:does_not_exist)
      end
    end

    test "resolve/1 resolves aliases to direct model specs" do
      inline_model = %{provider: :openai, id: "gpt-4.1", base_url: "http://localhost:4000/v1"}

      with_model_aliases(%{capable: inline_model}, fn ->
        assert Models.resolve(:capable) == inline_model
      end)
    end

    test "resolve/1 accepts ReqLLM tuple, inline map, and model struct inputs" do
      tuple_model = {:openai, "gpt-4.1", [reasoning_effort: :medium]}
      inline_model = %{provider: :openai, id: "gpt-4.1", base_url: "http://localhost:4000/v1"}
      struct_model = LLMDB.Model.new!(%{provider: :openai, id: "gpt-4.1"})

      assert Models.resolve(tuple_model) == tuple_model
      assert Models.resolve(inline_model) == inline_model
      assert Models.resolve(struct_model) == struct_model
    end

    test "resolve/1 raises for invalid configured alias specs" do
      with_model_aliases(%{capable: [:invalid]}, fn ->
        assert_raise ArgumentError, ~r/Invalid model configured for alias :capable/, fn ->
          Models.resolve(:capable)
        end
      end)
    end

    test "resolve/1 raises for unsupported direct model inputs" do
      assert_raise ArgumentError, ~r/Expected a valid ReqLLM model input/, fn ->
        Models.resolve(123)
      end
    end
  end
end
