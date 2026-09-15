defmodule Jido.ThreadValueTest do
  use ExUnit.Case, async: true

  alias Jido.{Session, Thread}
  alias Jido.AI.Thread.Control
  alias Jido.Thread.Entry

  test "exposes schemas and empty value helpers" do
    assert %Zoi.Types.Struct{} = Entry.schema()
    assert %Zoi.Types.Struct{} = Thread.schema()
    assert %Zoi.Types.Struct{} = Session.schema()

    thread = Thread.new(now: 10)
    assert Thread.append(thread, nil) == thread
    assert Thread.append(thread, []) == thread
    assert Thread.last(thread) == nil
    assert Thread.filter_by_kind(nil, :note) == []

    session = Session.new(now: 10)
    assert Session.append(session, nil) == session
    assert Session.append(session, []) == session
    closed = Session.close(session)
    assert Session.close(closed) == closed
  end

  test "Entry rejects invalid input and decodes supported kind forms" do
    assert {:error, :invalid_entry} = Entry.decode(:invalid)
    assert {:error, :invalid_entry} = Entry.validate(:invalid)
    assert {:error, :invalid_entry} = Entry.decode(%{"unknown" => true})

    base = %{
      "id" => "entry",
      "seq" => 0,
      "at" => 10,
      "payload" => %{},
      "refs" => %{}
    }

    assert {:ok, %{kind: :note}} = Entry.decode(Map.put(base, "kind", :note))
    assert {:ok, %{kind: "custom"}} = Entry.decode(Map.put(base, "kind", "custom"))

    assert {:ok, %{kind: "custom"}} =
             Entry.decode(Map.put(base, "kind", %{"type" => "string", "value" => "custom"}))

    assert {:ok, %{kind: "raw"}} = Entry.decode(Map.put(base, "kind", "raw"))

    unknown_atom = "jido_ai_unknown_kind_#{System.unique_integer([:positive])}"

    assert {:error, :invalid_entry} =
             Entry.decode(Map.put(base, "kind", %{"type" => "atom", "value" => unknown_atom}))

    assert {:error, :invalid_entry} = Entry.decode(Map.put(base, "kind", ""))
  end

  test "Entry normalization fills missing optional fields" do
    entry = %Entry{id: nil, seq: 99, at: nil, kind: nil, payload: nil, refs: nil}
    normalized = Entry.normalize(entry, 3, 20)

    assert String.starts_with?(normalized.id, "entry_")
    assert normalized.seq == 3
    assert normalized.at == 20
    assert normalized.kind == :note
    assert normalized.payload == %{}
    assert normalized.refs == %{}
  end

  test "keeps an ordered portable log without runtime ownership" do
    thread =
      Thread.new(id: "context:test", now: 10)
      |> Thread.append(%{kind: :ai_message, payload: %{role: :user}, refs: %{request_id: "request"}})
      |> Thread.append([
        %{kind: :ai_context_operation, payload: %{op_id: "replace"}},
        %{kind: :ai_message, payload: %{role: :assistant}}
      ])

    assert thread.id == "context:test"
    assert thread.rev == 3
    assert Thread.entry_count(thread) == 3
    assert Thread.last(thread).kind == :ai_message
    assert Thread.get_entry(thread, 1).kind == :ai_context_operation
    assert Enum.map(Thread.slice(thread, 1, 2), & &1.seq) == [1, 2]

    assert Enum.map(Thread.to_list(thread), &{&1.seq, &1.kind}) == [
             {0, :ai_message},
             {1, :ai_context_operation},
             {2, :ai_message}
           ]

    assert Enum.map(Thread.filter_by_kind(thread, :ai_message), & &1.payload.role) == [
             :user,
             :assistant
           ]

    assert :ok = Jido.Action.validate_static_data(thread)
  end

  test "normalizes string keys and preserves explicit portable entry data" do
    thread =
      Thread.new(now: 10)
      |> Thread.append(%{
        "id" => "entry",
        "at" => 20,
        "kind" => :ai_message,
        "payload" => %{"role" => "user"},
        "refs" => %{"request_id" => "request"}
      })

    assert [entry] = Thread.to_list(thread)
    assert entry.id == "entry"
    assert entry.seq == 0
    assert entry.at == 20
    assert entry.payload == %{"role" => "user"}
    assert entry.refs == %{"request_id" => "request"}
  end

  test "encodes and decodes a portable Thread without creating unknown atoms" do
    thread =
      Thread.new(id: "thread", now: 10, metadata: %{owner: "agent"})
      |> Thread.append(%{id: "entry", at: 20, kind: "application.custom", payload: %{value: 1}})

    document = Thread.encode(thread)

    assert document["type"] == "jido.thread"
    assert {:ok, ^thread} = Thread.decode(document)
    assert {:error, :unsupported_version} = Thread.decode(%{document | "version" => 2})
    assert {:error, :invalid_thread} = Thread.decode(Map.put(document, "unknown", true))
    assert {:ok, ^thread} = Thread.decode(thread)
    assert {:error, :invalid_thread} = Thread.decode(:invalid)
    assert {:error, :invalid_thread} = Thread.validate(:invalid)
    assert {:error, :invalid_thread} = Thread.decode(%{document | "entries" => :invalid})

    assert {:error, :unsupported_version} =
             document |> Map.delete("type") |> Thread.decode()

    assert {:error, :invalid_thread} =
             Thread.decode(%{document | "entries" => [%{"bad" => true}]})
  end

  test "filters by one kind or a list of kinds" do
    thread =
      Thread.new(now: 10)
      |> Thread.append([
        %{id: "one", at: 10, kind: :note},
        %{id: "two", at: 10, kind: "custom"},
        %{id: "three", at: 10, kind: :message}
      ])

    assert Enum.map(Thread.filter_by_kind(thread, [:note, :message]), & &1.id) == ["one", "three"]
    assert Enum.map(Thread.filter_by_kind(thread, "custom"), & &1.id) == ["two"]
  end

  test "rejects nonportable Thread data" do
    assert_raise ArgumentError, fn ->
      Thread.new(metadata: %{owner: self()})
    end

    assert_raise ArgumentError, fn ->
      Thread.new() |> Thread.append(%{payload: %{callback: fn -> :ok end}})
    end
  end

  test "Entry creates complete portable values" do
    entry = Entry.new(kind: :note, payload: %{text: "saved"})

    assert String.starts_with?(entry.id, "entry_")
    assert entry.seq == 0
    assert is_integer(entry.at)
    assert {:ok, ^entry} = entry |> Entry.encode() |> Entry.decode()
  end

  test "Session owns one Thread and has a separate lifecycle revision" do
    session = Session.new(id: "session", now: 10, metadata: %{profile: :assistant})
    assert session.thread.id == "session:thread"
    assert session.rev == 0
    assert Session.open?(session)

    session = Session.append(session, %{id: "entry", at: 20, kind: :ai_message})
    assert session.rev == 1
    assert session.thread.rev == 1

    session = Session.put_metadata(session, %{profile: :review})
    assert session.rev == 2
    assert session.thread.rev == 1

    session = Session.close(session)
    refute Session.open?(session)
    assert session.rev == 3
    assert_raise ArgumentError, fn -> Session.append(session, %{kind: :note}) end
  end

  test "encodes and decodes a portable Session" do
    session =
      Session.new(id: "session", now: 10)
      |> Session.append(%{id: "entry", at: 20, kind: :note})

    assert {:ok, ^session} = session |> Session.encode() |> Session.decode()

    document = Session.encode(session)
    assert {:error, :unsupported_version} = Session.decode(%{document | "version" => 2})
    assert {:error, :invalid_session} = Session.decode(Map.put(document, "unknown", true))
    assert {:ok, ^session} = Session.decode(session)
    assert {:error, :invalid_session} = Session.decode(:invalid)
    assert {:error, :invalid_session} = Session.validate(:invalid)
    assert {:error, :invalid_session} = Session.decode(%{document | "status" => "invalid"})

    atom_document = %{document | "status" => :open}
    assert {:ok, %{status: :open}} = Session.decode(atom_document)

    assert {:ok, %{status: :closed}} = Session.decode(%{document | "status" => :closed})
    assert {:ok, %{status: :closed}} = Session.decode(%{document | "status" => "closed"})

    assert {:error, :unsupported_version} =
             document |> Map.delete("type") |> Session.decode()
  end

  test "builds a Session around an existing Thread" do
    thread = Thread.new(id: "existing", now: 10)

    session =
      Session.from_thread(thread,
        id: "wrapped",
        created_at: 9,
        updated_at: 11,
        metadata: %{owner: "test"}
      )

    assert session.id == "wrapped"
    assert session.thread == thread
    assert session.created_at == 9
    assert session.updated_at == 11
    assert session.metadata == %{owner: "test"}

    assert_raise ArgumentError, "invalid session metadata", fn ->
      Session.put_metadata(session, %{owner: self()})
    end
  end

  test "context operation helpers expose keys and active refs" do
    assert Control.key() == :jido_ai_contexts
    assert Control.type() == "jido.ai.context.modify"
    assert Control.active_ref(%{}, :assistant) == "default"

    assert Control.active_ref(%{Control.key() => %{assistant: %{active_context_ref: "saved"}}}, :assistant) ==
             "saved"
  end

  test "context operation validation handles valid, invalid, and exceptional saved values" do
    lane = %{
      active_context_ref: "default",
      pending_context_op: nil,
      applied_context_ops: []
    }

    assert :ok = Control.validate_state(%{assistant: lane}, %{assistant: %{}}, nil)
    assert {:error, "Expected context lanes"} = Control.validate_state(:invalid, %{}, nil)

    assert {:error, "Expected portable context lanes for declared profiles"} =
             Control.validate_state(%{assistant: %{}}, %{assistant: %{}}, nil)

    assert {:error, "Invalid saved context data"} =
             Control.validate_state(%{assistant: lane}, :invalid, nil)
  end

  test "context lanes reject a duplicate conversation store" do
    lane = %{active_context_ref: "default", pending_context_op: nil, applied_context_ops: [], session: Session.new()}
    assert {:error, _} = Control.validate_state(%{assistant: lane}, %{assistant: %{}}, nil)
  end
end
