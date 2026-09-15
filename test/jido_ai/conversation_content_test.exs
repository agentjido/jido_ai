defmodule Jido.AI.ConversationContentTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Conversation
  alias ReqLLM.{Context, Message}
  alias ReqLLM.Message.ContentPart

  test "all supported content parts retain order and data across Session JSON" do
    parts = [
      ContentPart.thinking("reason", %{"signature" => "opaque"}),
      ContentPart.text("answer"),
      ContentPart.image_url("https://example.com/image.png"),
      %ContentPart{type: :video_url, url: "https://example.com/video.mp4"},
      ContentPart.image(<<255, 0, 128>>, "image/png"),
      ContentPart.file(<<255, 10>>, "report.pdf", "application/pdf"),
      ContentPart.file_id("file-1", "application/pdf")
    ]

    {:ok, session} = Conversation.append(Jido.Session.new(), [%Message{role: :assistant, content: parts}])

    assert {:ok, restored} =
             session |> Jido.Session.encode() |> Jason.encode!() |> Jason.decode!() |> Jido.Session.decode()

    assert {:ok, [%{content: ^parts}]} = Conversation.messages(restored)
  end

  test "multimodal tool results retain correlation and content" do
    parts = [ContentPart.text("4"), ContentPart.image_url("https://example.com/chart.png")]

    messages = [
      Context.user("Calculate"),
      %Message{role: :assistant, content: [], tool_calls: [ReqLLM.ToolCall.new("call", "calc", "{}")]},
      %Message{role: :tool, name: "calc", tool_call_id: "call", content: parts}
    ]

    {:ok, thread} = Conversation.append(Jido.Thread.new(), messages)
    assert {:ok, [_, _, %{name: "calc", tool_call_id: "call", content: ^parts}]} = Conversation.messages(thread)
  end

  test "references stay on each canonical entry and survive mixed empty references" do
    input = [
      {Context.user("one"), %{source: "one"}},
      {Context.assistant("two"), %{}},
      {Context.tool_result("call", "calc", "3"), %{source: "three"}}
    ]

    thread =
      Enum.reduce(input, Jido.Thread.new(), fn {message, refs}, thread ->
        {:ok, next} = Conversation.append(thread, [message], refs)
        next
      end)

    assert {:ok, restored} =
             thread |> Jido.Thread.encode() |> Jason.encode!() |> Jason.decode!() |> Jido.Thread.decode()

    assert Enum.map(restored.entries, & &1.refs) == [%{"source" => "one"}, %{}, %{"source" => "three"}]
    assert {:ok, messages} = Conversation.messages(restored)
    assert Enum.all?(messages, &(&1.metadata == %{}))
    assert Enum.map(restored.entries, & &1.id) == Enum.map(thread.entries, & &1.id)
    assert Enum.map(restored.entries, & &1.at) == Enum.map(thread.entries, & &1.at)
  end

  test "system messages are explicit and metadata does not create a second message" do
    {:ok, thread} =
      Conversation.append(Jido.Thread.new(metadata: %{system_prompt: "metadata"}), [Context.system("explicit")])

    assert {:ok, [message]} = Conversation.messages(thread)
    assert hd(message.content).text == "explicit"
    assert {:ok, []} = Conversation.messages(Jido.Thread.new())
  end
end
