defmodule Jido.AI.Observe.ContentTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Observe.Content
  alias ReqLLM.Message.ContentPart

  for stream <- [false, true], stored <- [false, true] do
    test "tool permissions are independent: stream #{stream}, storage #{stored}" do
      call = ReqLLM.ToolCall.new("one", "read", ~s({"path":"private"}))
      policy = %{stream_content: unquote(stream), store_content: unquote(stored)}
      assert Content.project(call, policy, :stream) == call == unquote(stream)
      assert Content.project(call, policy, :storage) == call == unquote(stored)

      event = %{kind: :tool_completed, data: %{tool_call_id: "one", result: {:ok, "private result"}}}
      assert Content.event(event, policy, :stream) == event == unquote(stream)
      assert Content.event(event, policy, :storage) == event == unquote(stored)
    end

    test "media permissions are independent: stream #{stream}, storage #{stored}" do
      image = ContentPart.image("private image", "image/png")
      policy = %{stream_content: unquote(stream), store_content: unquote(stored)}
      assert Content.project(image, policy, :stream) == image == unquote(stream)
      assert Content.project(image, policy, :storage) == image == unquote(stored)
      refute Content.project(image, policy, :diagnostics, true) == image
    end

    test "reasoning permissions are independent: stream #{stream}, storage #{stored}" do
      value = %{thinking_content: "private thought", text: "public answer"}

      policy = %{
        stream_reasoning: unquote(stream),
        store_reasoning: unquote(stored),
        stream_content: true,
        store_content: true
      }

      assert Content.project(value, policy, :stream).thinking_content ==
               if(unquote(stream), do: "private thought", else: "")

      assert Content.project(value, policy, :storage).thinking_content ==
               if(unquote(stored), do: "private thought", else: "")

      assert Content.project(value, policy, :stream).text == "public answer"
    end
  end

  test "diagnostics require both trusted policy and explicit access" do
    value = %{query: "private", checkpoint_token: "signed but not encrypted"}
    assert Content.project(value, %{}, :diagnostics, true) == %{query: "", checkpoint_token: nil}
    assert Content.project(value, %{diagnostics_content: true}, :diagnostics) == %{query: "", checkpoint_token: nil}
    assert Content.project(value, %{diagnostics_content: true}, :diagnostics, true) == value
  end

  test "default storage removes tool messages without changing execution input" do
    message = ReqLLM.Context.tool_result("one", "private result")
    assert {redacted, true} = Content.message(message, %{})
    refute inspect(redacted) =~ "private result"
    refute inspect(Content.project(%{messages: [message]}, %{}, :storage)) =~ "private result"
    refute Content.retainable?(%{messages: [message]}, %{})
    assert {^message, false} = Content.message(message, %{store_content: true})
  end

  test "native and encoded content have the same default protection" do
    encoded = %{"type" => "image", "data" => Base.encode64("private image"), "data_encoding" => "base64"}
    refute inspect(Content.project(encoded, %{}, :storage)) =~ encoded["data"]
    assert Content.project(encoded, %{store_content: true}, :storage) == encoded
  end

  test "permitted tool arguments still remove credentials without changing native input" do
    call = ReqLLM.ToolCall.new("one", "read", ~s({"password":"private","n":1}))
    projected = Content.project(call, %{stream_content: true}, :stream)
    assert Jason.decode!(projected.function.arguments) == %{"password" => "[REDACTED]", "n" => 1}
    assert Jason.decode!(call.function.arguments)["password"] == "private"
    assert Content.project(call, %{}, :stream).function.arguments == "{}"
  end

  test "checkpoint export requires both content permissions and cannot retain credentials" do
    value = %{context: [ContentPart.image("private image", "image/png")]}
    refute Content.retainable?(value, %{store_content: true})
    assert Content.retainable?(value, %{store_content: true, stream_content: true})
    refute Content.retainable?(%{api_key: "private"}, %{store_content: true, stream_content: true})
  end

  test "projection bounds collections and accepts malformed tool-result collections" do
    assert length(Content.project(Enum.to_list(1..3_000), %{}, :storage)) == 2_000
    assert map_size(Content.project(Map.new(1..3_000, &{&1, &1}), %{}, :storage)) == 2_000
    assert Content.project(%{tool_results: [nil, :bad, 1]}, %{}, :stream).tool_results == [nil, :bad, 1]
    value = String.duplicate("界", 30_000)
    projected = Content.project(value, %{}, :storage)
    assert String.valid?(projected) and byte_size(projected) < 66_000
  end
end
