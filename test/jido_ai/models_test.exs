defmodule Jido.AI.ModelsTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Models

  setup do
    original = Application.get_env(:jido_ai, :model_aliases)

    Application.put_env(:jido_ai, :model_aliases, %{
      fast: "openai:gpt-4o-mini",
      invalid: 123
    })

    on_exit(fn -> restore_aliases(original) end)
  end

  test "resolves configured aliases and direct model names" do
    assert Models.resolve(:fast) == {:ok, "openai:gpt-4o-mini"}
    assert Models.resolve("anthropic:claude-haiku-4-5") == {:ok, "anthropic:claude-haiku-4-5"}
  end

  test "returns clear errors for unknown and invalid aliases" do
    assert Models.resolve(:missing) == {:error, {:unknown_model_alias, :missing}}
    assert Models.resolve(:invalid) == {:error, {:invalid_model_alias, :invalid, 123}}
  end

  defp restore_aliases(nil), do: Application.delete_env(:jido_ai, :model_aliases)
  defp restore_aliases(aliases), do: Application.put_env(:jido_ai, :model_aliases, aliases)
end
