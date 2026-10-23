defmodule Jido.SessionTest do
  use ExUnit.Case, async: true

  test "a Session appends through its Thread and closes once" do
    request = Jido.Signal.new!("test.session.request", %{text: "Hello"}, source: "/test")
    session = Jido.Session.new!(id: "session-1", metadata: %{channel: "test"})

    assert {:ok, open} = Jido.Session.append(session, request)
    assert open.status == :open
    assert open.thread.signals == [request]
    assert session.thread.signals == []

    assert {:ok, closed} = Jido.Session.close(open)
    assert closed.status == :closed
    assert Jido.Session.close(closed) == {:ok, closed}
    assert Jido.Session.append(closed, request) == {:error, :session_closed}
    assert Jido.PortableTerm.valid?(closed)
  end

  test "a Session rejects runtime-only metadata" do
    assert {:error, {:nonportable, [:session, :metadata, :owner]}} =
             Jido.Session.new(metadata: %{owner: self()})
  end

  test "a Session rejects an invalid supplied Thread" do
    invalid_thread = %{Jido.Thread.new!() | rev: 1}

    assert Jido.Session.new(thread: invalid_thread) ==
             {:error, :invalid_thread_revision}
  end
end
