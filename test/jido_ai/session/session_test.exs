defmodule Jido.AI.SessionTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Request.Handle
  alias Jido.AI.Session

  test "cancel returns a stable error when the server is unavailable" do
    server = spawn(fn -> :ok end)
    monitor = Process.monitor(server)
    assert_receive {:DOWN, ^monitor, :process, ^server, _reason}

    handle = Handle.new("req_cancel", server, "query")

    assert {:error, :agent_server_unavailable} = Session.cancel(handle)
  end
end
