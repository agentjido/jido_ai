defmodule Jido.DialogueTest do
  use ExUnit.Case
  doctest Jido.Dialogue

  test "greets the world" do
    assert Jido.Dialogue.hello() == :world
  end
end
