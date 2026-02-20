defmodule Jido.AI.SecurityCutoverTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  test "Jido.AI.Security module is removed" do
    refute Code.ensure_loaded?(Jido.AI.Security)
  end

  test "lib has no Jido.AI.Security references" do
    refs =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        path
        |> File.read!()
        |> String.contains?("Jido.AI.Security")
      end)

    assert refs == []
  end
end
