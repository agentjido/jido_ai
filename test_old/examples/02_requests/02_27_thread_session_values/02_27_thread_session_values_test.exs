defmodule JidoAI.Examples.ThreadSessionValuesTest do
  use ExUnit.Case, async: true

  alias Jido.{Session, Thread}
  alias JidoAI.Examples.ThreadSessionValues, as: Example

  @moduletag :example

  test "an application builds immutable ordered history" do
    first = Example.open_case("case-42", "What changed?", now: 10, request_id: "request-1")

    assert %Session{id: "support:case-42", rev: 1, status: :open} = first
    assert first.metadata == %{case_id: "case-42"}
    assert first.thread.id == "support:case-42:thread"
    assert Example.messages(first) == [{:user, "What changed?"}]

    answered = Example.record_answer(first, "Portable history changed.", at: 20, request_id: "request-1")

    assert first.rev == 1
    assert Thread.entry_count(first.thread) == 1
    assert answered.rev == 2
    assert Thread.entry_count(answered.thread) == 2
    assert Enum.map(Thread.to_list(answered.thread), & &1.seq) == [0, 1]

    assert Example.messages(answered) == [
             {:user, "What changed?"},
             {:assistant, "Portable history changed."}
           ]

    assert Thread.last(answered.thread).refs == %{request_id: "request-1"}
  end

  test "Thread supports direct selection without a runtime" do
    empty = Thread.new(id: "audit", now: 10)

    thread =
      Thread.append(empty, [
        %{id: "entry-1", at: 11, kind: :ai_message, payload: %{role: :user}},
        %{id: "entry-2", at: 12, kind: :case_note, payload: %{status: "open"}},
        %{id: "entry-3", at: 13, kind: :ai_message, payload: %{role: :assistant}}
      ])

    assert empty.entries == []
    assert empty.rev == 0
    assert thread.rev == 3
    assert Thread.entry_count(thread) == 3
    assert Thread.get_entry(thread, 1).id == "entry-2"
    assert Enum.map(Thread.filter_by_kind(thread, :ai_message), & &1.id) == ["entry-1", "entry-3"]
    assert Enum.map(Thread.slice(thread, 1, 2), & &1.id) == ["entry-2", "entry-3"]
  end

  test "Session lifecycle changes do not alter its Thread" do
    thread = Thread.new(id: "existing", now: 10) |> Thread.append(%{id: "note", at: 11, kind: :note})
    session = Session.from_thread(thread, id: "session", created_at: 10, updated_at: thread.updated_at)

    changed = Session.put_metadata(session, %{owner: "support"})
    closed = Session.close(changed)

    assert session.rev == thread.rev
    assert changed.rev == session.rev + 1
    assert changed.thread == session.thread
    assert closed.rev == changed.rev + 1
    refute Session.open?(closed)
    assert Session.close(closed) == closed

    assert_raise ArgumentError, ~r/cannot append to a closed session/, fn ->
      Session.append(closed, %{kind: :note})
    end
  end

  test "versioned documents round-trip and reject runtime data" do
    session =
      Example.open_case("case-7", "Save this", now: 10)
      |> Example.record_answer("Saved", at: 20)

    document = Example.export(session)

    assert document["type"] == "jido.session"
    assert document["version"] == 1
    assert document["thread"]["type"] == "jido.thread"
    assert {:ok, ^session} = Example.restore(document)
    assert {:error, :unsupported_version} = Example.restore(%{document | "version" => 2})
    assert {:error, :invalid_session} = Example.restore(Map.put(document, "unknown", true))

    assert_raise ArgumentError, ~r/invalid session/, fn ->
      Session.new(metadata: %{owner: self()})
    end

    assert_raise ArgumentError, ~r/invalid thread entry/, fn ->
      Thread.new() |> Thread.append(%{payload: %{callback: fn -> :ok end}})
    end
  end
end
