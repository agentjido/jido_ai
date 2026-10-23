defmodule JidoAI.Examples.ModelHelpersTest do
  use ExUnit.Case, async: false

  alias Jido.AI.{Models, Plugin}
  alias JidoAI.Examples.ModelHelpers.{FastAgent, PinnedAgent}

  @moduletag :example

  test "aliases and direct model names resolve explicitly" do
    assert Plugin.config(FastAgent).model == :fast
    assert Models.resolve(:fast) == {:ok, "openai:gpt-4o-mini"}

    direct = Plugin.config(PinnedAgent).model
    assert Models.resolve(direct) == {:ok, "anthropic:claude-haiku-4-5"}

    assert Models.resolve(:missing) == {:error, {:unknown_model_alias, :missing}}
  end
end
