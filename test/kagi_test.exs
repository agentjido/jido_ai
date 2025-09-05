defmodule KagiTest do
  use ExUnit.Case
  doctest Kagi

  test "greets the world" do
    assert Kagi.hello() == :world
  end
end
