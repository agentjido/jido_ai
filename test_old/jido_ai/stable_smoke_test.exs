defmodule Jido.AI.StableSmokeTest do
  use ExUnit.Case, async: true

  @moduletag :stable_smoke
  @moduletag :unit

  test "mix aliases expose the stable gate contract" do
    aliases = Mix.Project.config()[:aliases] || []

    assert Keyword.fetch!(aliases, :test) == "test --exclude flaky"

    assert Keyword.fetch!(aliases, :"test.fast") ==
             "cmd env MIX_ENV=test mix test --exclude flaky --only stable_smoke"

    precommit_steps = Keyword.fetch!(aliases, :precommit)
    assert is_list(precommit_steps)
    assert "test.fast" in precommit_steps

    quality_steps = Keyword.fetch!(aliases, :quality)
    assert is_list(quality_steps)
    assert "dialyzer" in quality_steps
  end
end
