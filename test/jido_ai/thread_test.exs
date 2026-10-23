defmodule Jido.ThreadTest do
  use ExUnit.Case, async: true

  defmodule Ask do
    use Jido.SignalAction,
      name: "thread_test_ask",
      description: "Ask one question",
      vsn: 1,
      input: [
        type: "test.thread.ask",
        default_source: "/test/thread/client",
        schema: Zoi.object(%{question: Zoi.string()})
      ],
      output: [
        type: "test.thread.answered",
        default_source: "/test/thread",
        schema: Zoi.object(%{answer: Zoi.string()})
      ]

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{answer: "Ready"}}
  end

  test "a Thread keeps correlated Signals in order without changing the old value" do
    request = Ask.new!(%{question: "Ready?"})
    {:ok, reply} = Ask.reply(request, %{answer: "Ready"})
    original = Jido.Thread.new!(id: "thread-1", metadata: %{topic: "status"})

    assert {:ok, thread} = Jido.Thread.append_many(original, [request, reply])
    assert original.rev == 0
    assert original.signals == []
    assert thread.rev == 2
    assert thread.signals == [request, reply]
    assert Jido.Signal.get_context(reply, "jidocausationid") == request.id
    assert Jido.PortableTerm.valid?(thread)
  end

  test "a Thread rejects runtime-only metadata and Signal data" do
    assert {:error, {:nonportable, [:thread, :metadata, :owner]}} =
             Jido.Thread.new(metadata: %{owner: self()})

    signal = Jido.Signal.new!("test.thread.runtime", %{owner: self()}, source: "/test")
    thread = Jido.Thread.new!()

    assert {:error, {:nonportable, [:thread, :signals, 0, :data, :owner]}} =
             Jido.Thread.append(thread, signal)

    assert thread.rev == 0
  end

  test "a Signal batch is rejected without a partial append" do
    valid = Jido.Signal.new!("test.thread.valid", %{}, source: "/test")
    invalid = Jido.Signal.new!("test.thread.invalid", %{owner: self()}, source: "/test")
    thread = Jido.Thread.new!()

    assert {:error, {:nonportable, _path}} =
             Jido.Thread.append_many(thread, [valid, invalid])

    assert thread.rev == 0
    assert thread.signals == []
  end
end
