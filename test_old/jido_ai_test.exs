defmodule Jido.AITest do
  use ExUnit.Case, async: true

  alias Jido.AI
  alias Jido.AI.Models

  doctest AI

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
    test "loads package configuration defaults" do
      assert is_binary(Models.resolve(:fast))
    end

    test "merges configured aliases over defaults" do
      with_model_aliases(%{fast: "openai:gpt-4o-mini", custom: "openai:gpt-4.1"}, fn ->
        assert Models.resolve(:fast) == "openai:gpt-4o-mini"
        assert Models.resolve(:custom) == "openai:gpt-4.1"
      end)
    end

    test "configured aliases can resolve to direct model specs" do
      model = %{provider: :openai, id: "gpt-4.1", base_url: "http://localhost:4000/v1"}
      with_model_aliases(%{capable: model}, fn -> assert Models.resolve(:capable) == model end)
    end
  end
end
