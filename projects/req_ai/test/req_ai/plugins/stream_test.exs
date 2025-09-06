defmodule ReqAI.Plugins.StreamTest do
  use ExUnit.Case, async: true

  alias ReqAI.Plugins.Stream

  describe "attach/1" do
    test "attaches stream_sse step to response" do
      req = Req.new() |> Stream.attach()

      assert Enum.any?(req.response_steps, fn
               {:stream_sse, _fun} -> true
               _ -> false
             end)
    end
  end

  describe "process_sse_response/1" do
    test "processes SSE response into stream" do
      sse_body = """
      event: delta
      data: {"content": "Hello"}

      event: done
      data: [DONE]

      """

      response = %Req.Response{
        status: 200,
        headers: %{"content-type" => ["text/event-stream"]},
        body: sse_body
      }

      result = Stream.process_sse_response(response)

      # The body should be a streamable enumerable (Elixir Stream struct)  
      assert is_struct(result.body, Elixir.Stream)
      chunks = Enum.to_list(result.body)

      assert length(chunks) == 2
      assert %{event: "delta", data: %{"content" => "Hello"}} = Enum.at(chunks, 0)
      assert %{event: "done", data: "[DONE]"} = Enum.at(chunks, 1)
    end

    test "passes through non-SSE responses unchanged" do
      response = %Req.Response{
        status: 200,
        headers: %{"content-type" => ["application/json"]},
        body: ~s({"message": "Hello"})
      }

      result = Stream.process_sse_response(response)

      assert result == response
    end

    test "handles SSE with JSON data parsing" do
      sse_body = """
      data: {"type": "content_block_delta", "delta": {"text": "Hello"}}

      """

      response = %Req.Response{
        status: 200,
        headers: %{"content-type" => ["text/event-stream; charset=utf-8"]},
        body: sse_body
      }

      result = Stream.process_sse_response(response)
      chunks = Enum.to_list(result.body)

      assert length(chunks) == 1

      assert %{data: %{"type" => "content_block_delta", "delta" => %{"text" => "Hello"}}} =
               Enum.at(chunks, 0)
    end

    test "handles SSE with plain text data" do
      sse_body = """
      event: message
      data: Plain text message

      """

      response = %Req.Response{
        status: 200,
        headers: %{"content-type" => ["text/event-stream"]},
        body: sse_body
      }

      result = Stream.process_sse_response(response)
      chunks = Enum.to_list(result.body)

      assert length(chunks) == 1
      assert %{event: "message", data: "Plain text message"} = Enum.at(chunks, 0)
    end

    test "handles SSE with retry and id fields" do
      sse_body = """
      id: 123
      event: update
      data: {"status": "processing"}
      retry: 3000

      """

      response = %Req.Response{
        status: 200,
        headers: %{"content-type" => ["text/event-stream"]},
        body: sse_body
      }

      result = Stream.process_sse_response(response)
      chunks = Enum.to_list(result.body)

      assert length(chunks) == 1
      chunk = Enum.at(chunks, 0)
      assert %{id: "123", event: "update", retry: 3000} = chunk
      assert %{"status" => "processing"} = chunk.data
    end
  end
end
