defmodule Jido.AI.NoTodoBacklogTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  test "repository has no todo backlog files" do
    refute File.dir?("todo")
    assert Path.wildcard("todo/**/*") == []
  end
end
