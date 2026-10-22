defmodule JidoAI.Examples.ModelHelpersTest do
  use ExUnit.Case, async: false

  alias Jido.AI.{Models, Plugin}
  alias JidoAI.Examples.ModelHelpers.{FastAgent, PinnedAgent}

  @moduletag :example

  setup do
    original = Application.get_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{fast: "openai:gpt-4o-mini"})
    on_exit(fn -> restore_aliases(original) end)
  end

  test "aliases and direct model names resolve explicitly" do
    assert Plugin.config(FastAgent).model == :fast
    assert Models.resolve(:fast) == {:ok, "openai:gpt-4o-mini"}

    direct = Plugin.config(PinnedAgent).model
    assert Models.resolve(direct) == {:ok, "anthropic:claude-haiku-4-5"}

    assert Models.resolve(:missing) == {:error, {:unknown_model_alias, :missing}}
  end

  defp restore_aliases(nil), do: Application.delete_env(:jido_ai, :model_aliases)
  defp restore_aliases(aliases), do: Application.put_env(:jido_ai, :model_aliases, aliases)
end
