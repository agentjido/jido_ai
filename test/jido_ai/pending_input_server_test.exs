defmodule Jido.AI.PendingInputServerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.PendingInputServer

  test "enqueue, drain, and has_pending? preserve FIFO order" do
    {:ok, server} = PendingInputServer.start_link(owner: self(), request_id: "req_fifo")

    assert :ok = PendingInputServer.enqueue(server, %{content: "first", source: "/test"})
    assert :ok = PendingInputServer.enqueue(server, %{content: "second", refs: %{origin: "suite"}})
    assert PendingInputServer.has_pending?(server)

    [first, second] = PendingInputServer.drain(server)

    assert first.content == "first"
    assert first.source == "/test"
    assert second.content == "second"
    assert second.refs == %{origin: "suite"}
    refute PendingInputServer.has_pending?(server)
  end

  test "seal_if_empty seals the queue and rejects later enqueue attempts" do
    {:ok, server} = PendingInputServer.start_link(owner: self(), request_id: "req_sealed")

    assert :sealed = PendingInputServer.seal_if_empty(server)
    assert {:error, :closed} = PendingInputServer.enqueue(server, %{content: "late"})
    assert [] == PendingInputServer.drain(server)
  end

  test "seal_if_empty leaves queued input available for drain" do
    {:ok, server} = PendingInputServer.start_link(owner: self(), request_id: "req_pending")

    assert :ok = PendingInputServer.enqueue(server, %{content: "queued"})
    assert :pending = PendingInputServer.seal_if_empty(server)
    assert [%{content: "queued"}] = PendingInputServer.drain(server)
    assert :ok = PendingInputServer.enqueue(server, %{content: "next"})
  end

  test "rejects blank input and enforces a bounded queue" do
    {:ok, server} =
      PendingInputServer.start_link(owner: self(), request_id: "req_bounded", max_queue_size: 2)

    assert {:error, :empty_content} = PendingInputServer.enqueue(server, %{content: "   "})
    assert :ok = PendingInputServer.enqueue(server, %{content: " first "})
    assert :ok = PendingInputServer.enqueue(server, %{content: "second"})
    assert {:error, :queue_full} = PendingInputServer.enqueue(server, %{content: "third"})

    assert [%{content: "first"}, %{content: "second"}] = PendingInputServer.drain(server)
  end

  test "server exits when its owner exits" do
    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, server} = PendingInputServer.start_link(owner: owner, request_id: "req_owner")
    monitor_ref = Process.monitor(server)

    send(owner, :stop)

    assert_receive {:DOWN, ^monitor_ref, :process, ^server, :normal}, 200
  end
end
