defmodule Jido.AI.Thread.SettlementProjectionTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Thread.Projection
  alias Jido.{Thread, Session}
  alias ReqLLM.{Context, Message, ToolCall}

  test "only a completed matching request attempt promotes pending evidence" do
    refs = %{request_id: "request", run_id: "attempt", conversation: :pending}
    {:ok, session} = Projection.append(Session.new(), [Context.user("private pending")], refs)
    assert {:ok, []} = Projection.messages(session)

    for {run, status} <- [{"other", :completed}, {"attempt", :failed}, {"attempt", :cancelled}] do
      entry =
        Thread.Entry.new(
          kind: :ai_request_settled,
          refs: %{request_id: "request", run_id: run},
          payload: %{status: status}
        )

      assert {:ok, []} = Projection.messages(Session.append(session, entry))
    end

    entry =
      Thread.Entry.new(kind: :ai_request_settled, refs: Map.delete(refs, :conversation), payload: %{status: :completed})

    assert {:ok, [message]} = Projection.messages(Session.append(session, entry))
    assert Jido.AI.Query.summarize(message.content) == "private pending"
    assert session.thread.rev == 1
  end

  test "an unresolved multi-call exchange is evidence, not model conversation" do
    assistant = %Message{
      role: :assistant,
      content: [],
      tool_calls: [ToolCall.new("a", "read", "{}"), ToolCall.new("b", "read", "{}")]
    }

    {:ok, thread} =
      Projection.append(Thread.new(), [Context.user("Work"), assistant, Context.tool_result("a", "read", "A")])

    assert {:ok, [%Message{role: :user}]} = Projection.messages(thread)
    assert length(thread.entries) == 3
    {:ok, finished} = Projection.append(thread, [Context.tool_result("b", "read", "B"), Context.assistant("Done")])
    assert {:ok, messages} = Projection.messages(finished)
    assert Enum.map(messages, & &1.role) == [:user, :assistant, :tool, :tool, :assistant]
    assert {:ok, %{}} = Projection.open_tool_calls(messages)
  end

  test "a redacted completed conversation rejects continuation instead of fabricating input" do
    profile =
      Jido.AI.Profile.new!(%{id: :assistant, model: :fast, memory: %{history: :messages}, result: %{into: :result}})

    entries = Jido.AI.Model.Messages.entries([Context.user([ReqLLM.Message.ContentPart.image("private", "image/png")])])
    session = Projection.append_entries(Session.new(), entries, %{}, profile.observability)

    assert {:error, :conversation_content_not_retained} =
             Jido.AI.Orchestration.Transcript.read(%{messages: session}, profile)

    refute :erlang.term_to_binary(session) =~ "private"
  end

  test "a mismatched tool name cannot complete an exchange" do
    assistant = %Message{role: :assistant, content: [], tool_calls: [ToolCall.new("a", "read", "{}")]}
    {:ok, thread} = Projection.append(Thread.new(), [assistant, Context.tool_result("a", "other", "not read")])
    assert {:ok, []} = Projection.messages(thread)
    assert length(thread.entries) == 2
  end
end
