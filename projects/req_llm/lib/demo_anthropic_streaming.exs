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

        # Process the streaming body
        if response.body do
          IO.puts("\n📡 Streaming content:")
          IO.puts("=" <> String.duplicate("=", 60))

          # The body should be a stream for Anthropic
          try do
            response.body
            |> Stream.each(fn chunk ->
              # Show progress
              IO.write(".")
              # In real implementation, this would parse SSE chunks
              # For now, just show we're receiving data
            end)
            |> Stream.run()

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

        # Process streaming response
        if response.body do
          IO.puts("\n📖 Streaming story:")
          IO.puts("=" <> String.duplicate("=", 60))

          try do
            # For demonstration, just show that we can iterate over the response
            case response.body do
              body when is_binary(body) ->
                IO.puts("📄 Non-streaming response received:")
                IO.puts(body)

              stream ->
                # This would be the actual streaming body
                stream
                |> Stream.each(fn chunk ->
                  # Show we're receiving chunks
                  IO.write("📡")
                  # Real implementation would parse SSE format and extract deltas
                end)
                |> Stream.run()
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
