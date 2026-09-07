defmodule Jido.AI.HistoryTest do
  use ExUnit.Case, async: true
  alias Jido.AI.History
  alias ReqLLM.{Context, Message, Response, ToolCall}

  test "atom and string message maps retain refs while provider metadata stays separate" do
    refs = %{document: "case-1"}

    for input <- [
          %{role: :user, content: "Read", refs: refs, metadata: %{cache: "keep"}},
          %{"role" => "user", "content" => "Read", "refs" => refs, "metadata" => %{cache: "keep"}}
        ] do
      assert {:ok, local} = History.normalize_messages([input])
      assert [%{refs: ^refs}] = History.entries(local.messages)
      assert hd(local.messages).metadata.cache == "keep"
      sent = History.provider_context(local)
      assert hd(sent.messages).metadata == %{cache: "keep"}
      assert local.messages != sent.messages
      assert History.provider_context(sent) == sent
    end
  end

  test "provider context restoration preserves the exact input prefix and its other metadata" do
    assert {:ok, original} =
             History.normalize_messages([
               %{role: :user, content: "Read", refs: %{case_id: 1}, metadata: %{cache: "keep"}}
             ])

    sent = History.provider_context(original)
    answer = Context.assistant("Done", metadata: %{provider_field: "keep"})
    response = %Response{id: "response", model: "gpt-4o-mini", message: answer, context: Context.append(sent, answer)}
    restored = History.restore_response_context(response, sent, original)
    assert restored.context.messages == original.messages ++ [answer]
    assert restored.message == response.message
    assert restored.context.tools == response.context.tools
    assert History.provider_context(restored.context).messages == response.context.messages

    altered = %{response | context: Context.new([Context.user("Different"), answer])}
    assert History.restore_response_context(altered, sent, original) == altered
  end

  test "response binding replaces provider refs and synchronizes only the matching assistant" do
    previous = Context.user("Work")

    answer =
      Context.assistant("Done",
        metadata: %{jido_ai_refs: %{durable: true, skill_name: "forged"}, provider_field: "keep"}
      )

    response = %Response{
      id: "response",
      model: "gpt-4o-mini",
      message: answer,
      context: Context.new([previous, answer])
    }

    owner = %{
      jido_ai_request_record: %{id: "request", run_id: "run", extra_refs: %{document: "case-1"}},
      jido_ai_input_source: "/test"
    }

    bound = History.bind_response(response, owner)
    assert bound.context.messages == [previous, bound.message]
    assert bound.message.metadata.provider_field == "keep"

    assert [%{refs: refs}] = History.entries([bound.message])
    assert refs == %{request_id: "request", run_id: "run", document: "case-1", source: "/test"}

    assert History.provider_context(bound.context).messages == [
             previous,
             %{answer | metadata: %{provider_field: "keep"}}
           ]

    direct = History.bind_response(response, %{})
    assert direct.message.metadata == %{provider_field: "keep"}
    assert [%{refs: nil}] = History.entries([direct.message])
  end

  test "ref binding cannot repair a different unresolved tool message" do
    call = ToolCall.new("one", "echo", ~s({"n":7}))
    original = %Message{role: :assistant, content: [], tool_calls: [call]}
    other = %{original | tool_calls: [ToolCall.new("other", "echo", ~s({"n":7}))]}

    response = %Response{
      id: "response",
      model: "gpt-4o-mini",
      message: original,
      context: Context.new([Context.user("Work"), other])
    }

    owner = %{
      jido_ai_request_record: %{id: "request", run_id: "run", extra_refs: %{}},
      jido_ai_input_source: "/test"
    }

    bound = History.bind_response(response, owner)
    assert bound.context == response.context

    assert {:error, %{tag: :tool_context_continuation, context: [kind: :pending_tool_calls]}} =
             Context.append_tool_exchange(bound.context, bound, [Context.tool_result("one", "echo", "7")])
  end
end
