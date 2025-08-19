defmodule Jido.Dialogue.SupervisorTest do
  use ExUnit.Case
  alias Jido.Dialogue.{DialogueManager, TestHelper}

  setup do
    TestHelper.start_supervised_app()
    on_exit(fn -> TestHelper.stop_supervised_app() end)
    :ok
  end

  test "starts the DialogueManager process" do
    assert Process.whereis(DialogueManager) != nil
  end
end
