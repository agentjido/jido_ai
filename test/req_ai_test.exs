defmodule ReqAiTest do
  use ExUnit.Case
  doctest ReqAi

  test "greets the world" do
    assert ReqAi.hello() == :world
  end
end
