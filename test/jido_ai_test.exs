defmodule JidoAiTest do
  use ExUnit.Case
  doctest JidoAi

  test "greets the world" do
    assert JidoAi.hello() == :world
  end
end
