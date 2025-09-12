#!/usr/bin/env mix run
# Demo script to test the Anthropic provider with streaming responses using raw Req approach
# Run with: mix run lib/demo_anthropic_streaming.exs

require Logger

defmodule AnthropicStreamingDemo do
  @moduledoc """
  Demo script to test the Anthropic provider streaming functionality using raw Req approach.
  This tests the lower-level streaming integration.
  """

  def run do
    IO.puts("=== ReqLLM Anthropic Provider Streaming Demo (Raw Req Approach) ===\n")

    # Check if we have an API key set
    api_key = JidoKeys.get("ANTHROPIC_API_KEY")

    if !api_key || api_key == "" do
      IO.puts("❌ Error: ANTHROPIC_API_KEY not found in JidoKeys")
      IO.puts("Please run: iex -S mix")
      IO.puts("Then: JidoKeys.put(\"ANTHROPIC_API_KEY\", \"your-key-here\")")
      exit(:normal)
    end

    IO.puts("✅ API key found (length: #{String.length(api_key)})")

    # Test streaming with raw Req approach
    test_simple_streaming()
    test_context_streaming()
  end

  defp test_simple_streaming do
    IO.puts("\n🎯 Testing simple streaming with raw Req...")

    # Create ReqLLM model
    {:ok, model} = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
    IO.puts("📋 Model: #{model.provider}:#{model.model}")

    # Create simple context with user message
    import ReqLLM.Context

    context =
      ReqLLM.Context.new([
        user("Count from 1 to 10, saying each number on a new line.")
      ])

    # Manual Req setup with streaming
    base_request = Req.new(url: "/messages")
    IO.puts("🔧 Base request created")

    # Attach Anthropic provider with streaming enabled
    attached_request =
      ReqLLM.Providers.Anthropic.attach(
        base_request,
        model,
        context: context,
        stream: true,
        max_tokens: 100
      )

    IO.puts("🔌 Anthropic provider attached with streaming")

    # Make the streaming request
    case Req.request(attached_request, method: :post) do
      {:ok, response} ->
        IO.puts("✅ Streaming request successful!")
        IO.puts("📊 HTTP Status: #{response.status}")
        IO.puts("🌊 Response is streamed")

        # Process the streaming body - should be a stream of SSE events
        if response.body do
          IO.puts("\n📡 Streaming content:")
          IO.puts("=" <> String.duplicate("=", 60))

          try do
            # Check if body is a stream (which it should be for SSE responses)
            case response.body do
              body when is_struct(body, Stream) ->
                IO.puts("✅ Response body is a stream!")

                # Process the stream chunks (SSE events)
                count =
                  body
                  |> Stream.with_index()
                  |> Stream.each(fn {chunk, idx} ->
                    IO.puts("📦 Chunk #{idx + 1}: #{inspect(chunk, limit: :infinity)}")

                    # Show parsed SSE event details
                    case chunk do
                      %{event: event, data: data} ->
                        IO.puts("   Event: #{inspect(event)}")
                        IO.puts("   Data: #{inspect(data)}")

                      _ ->
                        IO.puts("   Raw: #{inspect(chunk)}")
                    end
                  end)
                  |> Enum.count()

                IO.puts("\n📊 Processed #{count} streaming chunks")

              binary when is_binary(binary) ->
                IO.puts("📄 Response body is binary (non-streaming):")
                IO.puts(binary)

              other ->
                IO.puts("❓ Unknown response body type: #{inspect(other)}")
            end

            IO.puts("\n" <> String.duplicate("=", 60))
            IO.puts("✅ Stream processing complete!")
          catch
            :error, reason ->
              IO.puts("\n❌ Stream processing failed: #{inspect(reason)}")
          end
        else
          IO.puts("❌ No response body received")
        end

      {:error, error} ->
        IO.puts("❌ Streaming request failed:")
        IO.inspect(error, pretty: true)
    end
  end

  defp test_context_streaming do
    IO.puts("\n🎯 Testing context-based streaming with raw Req...")

    # Create ReqLLM model
    {:ok, model} = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

    # Create context with system and user messages
    import ReqLLM.Context

    context =
      ReqLLM.Context.new([
        system("You are a creative storyteller."),
        user("Tell me a very short story about a robot. Keep it under 50 words.")
      ])

    IO.puts("📨 Context has #{length(context.messages)} messages")

    # Manual Req setup with streaming and options
    base_request = Req.new(url: "/messages")

    attached_request =
      ReqLLM.Providers.Anthropic.attach(
        base_request,
        model,
        context: context,
        stream: true,
        temperature: 0.8,
        max_tokens: 100
      )

    # Make the streaming request
    case Req.request(attached_request, method: :post) do
      {:ok, response} ->
        IO.puts("✅ Context-based streaming request successful!")
        IO.puts("📊 HTTP Status: #{response.status}")

        # Show headers to understand the response format
        content_type = Req.Response.get_header(response, "content-type")
        IO.puts("📋 Content-Type: #{inspect(content_type)}")

        # Process streaming response - should be SSE events
        if response.body do
          IO.puts("\n📖 Streaming story:")
          IO.puts("=" <> String.duplicate("=", 60))

          try do
            case response.body do
              body when is_struct(body, Stream) ->
                IO.puts("✅ Response body is a stream of SSE events!")

                # Collect and show all streaming chunks
                chunks = Enum.to_list(body)
                IO.puts("📊 Total chunks received: #{length(chunks)}")

                # Show each chunk with details
                chunks
                |> Enum.with_index(1)
                |> Enum.each(fn {chunk, idx} ->
                  IO.puts("\n📦 Chunk #{idx}:")

                  case chunk do
                    %{event: event, data: data} ->
                      IO.puts("   Event Type: #{inspect(event)}")
                      IO.puts("   Data: #{inspect(data, limit: :infinity)}")

                      # Try to extract text content if available
                      if is_map(data) and Map.has_key?(data, "delta") do
                        delta = data["delta"]

                        if is_map(delta) and Map.has_key?(delta, "text") do
                          IO.puts("   📝 Text Delta: \"#{delta["text"]}\"")
                        end
                      end

                    _ ->
                      IO.puts("   Raw Chunk: #{inspect(chunk)}")
                  end
                end)

              binary when is_binary(binary) ->
                IO.puts("📄 Non-streaming response received:")
                # Try to decode as JSON and show nicely
                case Jason.decode(binary) do
                  {:ok, json} ->
                    IO.puts("JSON Response: #{inspect(json, pretty: true)}")

                  {:error, _} ->
                    IO.puts(binary)
                end

              other ->
                IO.puts("❓ Unknown response body type: #{inspect(other)}")
            end

            IO.puts("\n" <> String.duplicate("=", 60))
            IO.puts("✅ Story streaming complete!")
          catch
            :error, reason ->
              IO.puts("\n❌ Stream processing failed: #{inspect(reason)}")
          end
        else
          IO.puts("❌ No response body received")
        end

      {:error, error} ->
        IO.puts("❌ Context-based streaming request failed:")
        IO.inspect(error, pretty: true)
    end
  end
end

# Run the demo
AnthropicStreamingDemo.run()
