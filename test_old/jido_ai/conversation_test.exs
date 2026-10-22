defmodule Jido.AI.ConversationTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Thread.Projection
  alias ReqLLM.{Context, Message, ToolCall}
  alias ReqLLM.Message.ContentPart

  test "selection applies replacements and lane switches without changing the log" do
    {:ok, thread} = Projection.append(Jido.Thread.new(), [Context.user("old")])
    {:ok, thread} = Projection.append(thread, [Context.user("other")], %{context_ref: "other"})
    {:ok, snapshot} = Projection.append(Jido.Thread.new(), [Context.user("saved")])
    snapshot = Jido.Thread.append(snapshot, %{kind: :application_note, payload: %{private: "not a model message"}})

    replacement = %{
      "version" => 1,
      "op_id" => "replace",
      "context_ref" => "default",
      "operation" => %{
        "type" => "replace",
        "reason" => "manual",
        "result_context" => Jido.Thread.encode(snapshot),
        "base_seq" => nil,
        "meta" => %{}
      }
    }

    thread = Jido.Thread.append(thread, %{kind: :ai_context_operation, payload: replacement})
    {:ok, thread} = Projection.append(thread, [Context.user("next")])
    assert {:ok, messages} = Projection.messages(thread)
    assert Enum.map(messages, &hd(&1.content).text) == ["saved", "next"]
    assert length(thread.entries) == 4

    switch = %{
      replacement
      | "op_id" => "switch",
        "context_ref" => "other",
        "operation" => %{replacement["operation"] | "type" => "switch", "result_context" => nil}
    }

    thread = Jido.Thread.append(thread, %{kind: :ai_context_operation, payload: switch})
    {:ok, restored} = thread |> Jido.Thread.encode() |> Jason.encode!() |> Jason.decode!() |> Jido.Thread.decode()
    assert {:ok, [message]} = Projection.messages(restored)
    assert hd(message.content).text == "other"
    assert {:ok, other} = Projection.select(restored, "other")
    assert {:ok, [^message]} = Projection.messages(other)
    assert {:ok, selected} = Projection.select(restored, "default")
    assert {:ok, messages} = Projection.messages(selected)
    assert Enum.map(messages, &hd(&1.content).text) == ["saved", "next"]
  end

  test "canonical session survives JSON with tool correlation and references" do
    call = ToolCall.new("call-1", "multiply", ~s({"a":7,"b":13}))

    messages = [
      Context.user("Calculate"),
      %Message{role: :assistant, content: [], tool_calls: [call]},
      Context.tool_result("call-1", "multiply", "91"),
      Context.assistant("91 cents")
    ]

    {:ok, session} = Projection.append(Jido.Session.new(), messages, %{request_id: "r1"})
    encoded = session |> Jido.Session.encode() |> Jason.encode!() |> Jason.decode!()
    assert {:ok, restored} = Jido.Session.decode(encoded)
    assert {:ok, [_, assistant, tool, answer]} = Projection.messages(restored)
    assert hd(assistant.tool_calls).id == tool.tool_call_id
    assert tool.name == "multiply"
    assert hd(answer.content).text == "91 cents"
    assert hd(restored.thread.entries).refs["request_id"] == "r1"
    refute Map.has_key?(answer.metadata, :request_id)
  end

  test "binary and thinking content survive JSON without provider structs in payload" do
    parts = [
      %ContentPart{type: :image, data: <<255, 0, 128>>, media_type: "image/png"},
      %ContentPart{type: :thinking, text: "opaque", metadata: %{"signature" => "sig"}}
    ]

    {:ok, thread} = Projection.append(Jido.Thread.new(), [%Message{role: :assistant, content: parts}])
    {:ok, restored} = thread |> Jido.Thread.encode() |> Jason.encode!() |> Jason.decode!() |> Jido.Thread.decode()
    assert {:ok, [message]} = Projection.messages(restored)
    assert message.content == parts
    assert is_map(hd(hd(restored.entries).payload["content"]))
    refute is_struct(hd(hd(restored.entries).payload["content"]))
  end

  test "application entries are ignored but malformed AI entries fail" do
    thread = Jido.Thread.new() |> Jido.Thread.append(%{kind: :application_note, payload: %{text: "private"}})
    assert {:ok, []} = Projection.messages(thread)
    invalid = Jido.Thread.append(thread, %{kind: :ai_message, payload: %{"version" => 99}})
    assert {:error, :invalid_context} = Projection.messages(invalid)
    assert {:error, :invalid_context} = Jido.AI.Thread.Projection.project(invalid)
  end

  test "closed sessions do not accept messages" do
    session = Jido.Session.new() |> Jido.Session.close()
    assert {:error, :invalid_context} = Projection.append(session, [Context.user("hello")])
  end

  test "malformed AI payloads are rejected rather than silently projected" do
    {:ok, [entry]} = Projection.entries([Context.user("hello")])

    for payload <- [
          Map.put(entry.payload, "role", "unknown"),
          Map.put(entry.payload, "extra", true),
          Map.put(entry.payload, "role", "tool"),
          Map.put(entry.payload, "content", [%{"type" => "text", "text" => 42}])
        ] do
      assert {:error, :invalid_context} = Projection.message(%{entry | payload: payload})
    end
  end

  test "internal reference metadata does not become provider input" do
    message = Context.user("hello", %{"visible" => true, :jido_ai_refs => %{request_id: "private"}})
    {:ok, thread} = Projection.append(Jido.Thread.new(), [message], %{request_id: "private"})
    assert {:ok, [projected]} = Projection.messages(thread)
    assert projected.metadata == %{"visible" => true}
    assert hd(thread.entries).refs == %{request_id: "private"}
  end

  test "exchange validation rejects orphan results and preserves open checkpoint calls" do
    call = ToolCall.new("pending", "multiply", "{}")
    assistant = %Message{role: :assistant, content: [], tool_calls: [call]}
    assert {:ok, %{"pending" => _}} = Projection.open_tool_calls([assistant])

    assert {:error, :invalid_tool_history} =
             Projection.open_tool_calls([Context.tool_result("orphan", "multiply", "1")])

    assert {:error, :invalid_tool_history} = Projection.open_tool_calls([assistant, Context.user("interrupt")])
    assert {:ok, %{}} = Projection.open_tool_calls([assistant, Context.tool_result("pending", "multiply", "1")])
  end
end
