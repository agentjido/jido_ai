#!/usr/bin/env mix run
# Demo script to test the Anthropic provider with streaming responses
# Run with: mix run lib/demo_anthropic_streaming.exs

require Logger

defmodule AnthropicStreamingDemo do
  @moduledoc """
  Demo script to test the Anthropic provider streaming functionality using direct Req access.
  This script tests streaming with a longer prompt to see the response chunks arrive.
  """

  def run do
    IO.puts("=== ReqLLM Anthropic Provider Streaming Demo ===\n")

    # Check if we have an API key set
    api_key = JidoKeys.get("ANTHROPIC_API_KEY")

    if !api_key || api_key == "" do
      IO.puts("❌ Error: ANTHROPIC_API_KEY not found in JidoKeys")
      IO.puts("Please run: iex -S mix")
      IO.puts("Then: JidoKeys.put(\"ANTHROPIC_API_KEY\", \"your-key-here\")")
      exit(:normal)
    end

    IO.puts("✅ API key found (length: #{String.length(api_key)})")

    # Create a test model - using Claude Haiku for faster responses
    model_string = "anthropic:claude-3-haiku-20240307"
    IO.puts("🎯 Testing with model: #{model_string}")

    # Parse the model
    model = ReqLLM.Model.from!(model_string)
    IO.puts("📋 Parsed model:")
    IO.inspect(model, pretty: true, limit: :infinity)

    # Create proper ReqLLM context with a longer prompt that will generate more text
    import ReqLLM.Context

    context =
      ReqLLM.Context.new([
        user(
          "Please write a detailed explanation of how machine learning works, including the concepts of training data, algorithms, and predictions. Make it accessible for beginners and include specific examples."
        )
      ])

    IO.puts("\n📨 Test context:")
    IO.inspect(context, pretty: true, limit: :infinity)

    # Create the base Req request
    base_request = Req.new(url: "/messages")
    IO.puts("\n🔧 Base Req request:")
    IO.inspect(base_request, pretty: true, limit: :infinity)

    # Test options for streaming - set stream: true
    test_opts = [
      context: context,
      # Slightly higher temperature for more varied output
      temperature: 0.7,
      # Higher token limit for longer response
      max_tokens: 800,
      # Enable streaming
      stream: true
    ]

    IO.puts("\n⚙️  Test options:")
    IO.inspect(test_opts, pretty: true)

    # Attach the Anthropic provider
    IO.puts("\n🔗 Attaching Anthropic provider...")

    try do
      attached_request = ReqLLM.Providers.Anthropic.attach(base_request, model, test_opts)

      IO.puts("✅ Successfully attached provider")

      IO.puts(
        "\n📋 Stream option in attached request: #{inspect(attached_request.options[:stream])}"
      )

      # Make the streaming API call
      IO.puts("\n🚀 Making streaming API call...")
      IO.puts("📡 Streaming response:\n")
      IO.puts("=" <> String.duplicate("=", 50))
      
      case Req.request(attached_request, method: :post) do
        {:ok, response} ->
          IO.puts("✅ API call successful!")
          IO.puts("📊 Response status: #{response.status}")

          if response.status == 200 do
            handle_streaming_complete(response, context)
          else
            IO.puts("❌ Unexpected status code: #{response.status}")
            IO.puts("📋 Response body:")
            IO.inspect(response.body, pretty: true, limit: :infinity)
          end

        {:error, error} ->
          IO.puts("❌ API call failed:")
          IO.inspect(error, pretty: true, limit: :infinity)
      end
    rescue
      error ->
        IO.puts("❌ Error during provider attach:")
        IO.inspect(error, pretty: true, limit: :infinity)
        IO.puts("\nStacktrace:")
        IO.puts(Exception.format_stacktrace(__STACKTRACE__))
    end
  end

  defp handle_streaming_complete(response, _original_context) do
    IO.puts("\n\n" <> String.duplicate("=", 50))
    IO.puts("✅ Streaming completed!")
    IO.puts("📊 Response status: #{response.status}")

    case response.body do
      body_stream when is_struct(body_stream, Stream) ->
        IO.puts("📡 Processing streaming response chunks...")
        
        # Consume the stream and display the content with real-time streaming effect
        {accumulated_text, event_counts, usage_info} = 
          body_stream
          |> Enum.reduce({"", %{}, %{}}, fn chunk, {text_acc, counts, usage_acc} ->
            # Count event types
            event_type = get_event_type(chunk)
            new_counts = Map.update(counts, event_type, 1, &(&1 + 1))
            
            # Extract text content for real-time display
            text = extract_text_from_chunk(chunk)
            if text != "" do
              IO.write(text)
              # Small delay for visual streaming effect
              Process.sleep(10)
            end
            
            # Extract usage information
            new_usage = extract_usage_from_chunk(chunk, usage_acc)
            
            {text_acc <> text, new_counts, new_usage}
          end)
        
        # Summary statistics
        IO.puts("\n\n" <> String.duplicate("=", 50))
        IO.puts("📊 Streaming Summary:")
        IO.puts("📝 Total characters streamed: #{String.length(accumulated_text)}")
        IO.puts("📊 Event counts:")
        Enum.each(event_counts, fn {type, count} ->
          IO.puts("   #{type}: #{count}")
        end)
        
        if usage_info != %{} do
          IO.puts("📊 Token usage: #{Map.get(usage_info, :input_tokens, 0)} input, #{Map.get(usage_info, :output_tokens, 0)} output")
        end
        
      body when is_binary(body) ->
        IO.puts("📋 Received binary response:")
        IO.puts("📊 Response length: #{String.length(body)} bytes")
        IO.puts("First 200 chars: #{String.slice(body, 0, 200)}")
        
      other ->
        IO.puts("📋 Response body type: #{inspect(other.__struct__ || :unknown)}")
        IO.inspect(other, pretty: true, limit: 5)
    end
  end

  # Helper functions for the new streaming implementation
  
  defp get_event_type(chunk) do
    case chunk do
      %{event: event} -> event
      %{data: %{"type" => type}} -> type
      _ -> "unknown"
    end
  end
  
  defp extract_text_from_chunk(chunk) do
    case chunk do
      %{data: %{"type" => "content_block_delta", "delta" => %{"text" => text}}} ->
        text
      %{data: %{"delta" => %{"text" => text}}} ->
        text
      _ ->
        ""
    end
  end
  
  defp extract_usage_from_chunk(chunk, current_usage) do
    case chunk do
      %{data: %{"type" => "message_start", "message" => %{"usage" => usage}}} ->
        %{
          input_tokens: usage["input_tokens"],
          output_tokens: usage["output_tokens"]
        }
      %{data: %{"type" => "message_delta", "usage" => usage}} ->
        %{
          input_tokens: usage["input_tokens"],
          output_tokens: usage["output_tokens"]
        }
      _ ->
        current_usage
    end
  end

  # Additional demo functionality could be added here if needed
end

# Run the demo
AnthropicStreamingDemo.run()
