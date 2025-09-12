#!/usr/bin/env mix run
# Demo script to test the Anthropic provider with raw Req approach
# Run with: mix run lib/demo_anthropic.exs

require Logger

defmodule AnthropicDemo do
  @moduledoc """
  Demo script to test the Anthropic provider using raw Req approach.
  This tests the lower-level provider integration before high-level APIs.
  """

  def run do
    IO.puts("=== ReqLLM Anthropic Provider Demo (Raw Req Approach) ===\n")

    # Check if we have an API key set
    api_key = JidoKeys.get("ANTHROPIC_API_KEY")

    if !api_key || api_key == "" do
      IO.puts("❌ Error: ANTHROPIC_API_KEY not found in JidoKeys")
      IO.puts("Please run: iex -S mix")
      IO.puts("Then: JidoKeys.put(\"ANTHROPIC_API_KEY\", \"your-key-here\")")
      exit(:normal)
    end

    IO.puts("✅ API key found (length: #{String.length(api_key)})")

    # Test simple text generation with manual Req approach
    test_simple_generation()
    test_context_based_generation()
  end

  defp test_simple_generation do
    IO.puts("\n🎯 Testing simple text generation with raw Req...")

    # Create ReqLLM model
    {:ok, model} = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
    IO.puts("📋 Model: #{model.provider}:#{model.model}")

    # Create simple context with user message
    import ReqLLM.Context
    context = ReqLLM.Context.new([user("Say hello in exactly 3 words")])

    # Manual Req setup
    base_request = Req.new(url: "/messages")
    IO.puts("🔧 Base request created")

    # Attach Anthropic provider
    attached_request = ReqLLM.Providers.Anthropic.attach(base_request, model, context: context)
    IO.puts("🔌 Anthropic provider attached")

    # Make the request
    case Req.request(attached_request, method: :post) do
      {:ok, response} ->
        IO.puts("✅ Raw request successful!")
        IO.puts("📊 HTTP Status: #{response.status}")

        # Get raw JSON data and wrap it for proper decoding
        raw_data = response.body
        IO.puts("📄 Raw response data keys: #{inspect(Map.keys(raw_data))}")
        IO.puts("📄 Raw response content: #{inspect(raw_data["content"])}")
        IO.puts("📄 Raw response usage: #{inspect(raw_data["usage"])}")

        # Test direct decode using the provider's wrap_response function
        IO.puts("🔄 Testing zero-ceremony direct decode with wrapped response...")

        # Try both approaches: direct decode and wrapped decode
        IO.puts("🔄 Testing direct decode (zero-ceremony API)...")

        case ReqLLM.Response.Codec.decode_response(raw_data, model) do
          {:ok, decoded_response} ->
            IO.puts("✅ Direct decode successful!")
            IO.puts("📝 Response text: #{ReqLLM.Response.text(decoded_response)}")
            IO.puts("📊 Usage: #{inspect(ReqLLM.Response.usage(decoded_response))}")

            IO.puts(
              "🏁 Finish reason: #{inspect(ReqLLM.Response.finish_reason(decoded_response))}"
            )

          {:error, error} ->
            IO.puts("❌ Direct decode failed:")
            IO.inspect(error, pretty: true)
        end

        IO.puts("\n🔄 Testing wrapped decode (via ReqLLM.Response.decode)...")

        wrapped_response = ReqLLM.Providers.Anthropic.wrap_response(raw_data)
        IO.puts("🔧 DEBUG: Wrapped response: #{inspect(wrapped_response)}")

        case ReqLLM.Response.decode_response(wrapped_response, model) do
          {:ok, decoded_response} ->
            IO.puts("✅ Zero-ceremony decode successful!")
            IO.puts("📝 Response text: #{ReqLLM.Response.text(decoded_response)}")
            IO.puts("📊 Usage: #{inspect(ReqLLM.Response.usage(decoded_response))}")

            IO.puts(
              "🏁 Finish reason: #{inspect(ReqLLM.Response.finish_reason(decoded_response))}"
            )

            # Debug: show message content structure
            if decoded_response.message do
              IO.puts("🔍 Message content parts: #{length(decoded_response.message.content)}")

              Enum.with_index(decoded_response.message.content, 1)
              |> Enum.each(fn {part, idx} ->
                IO.puts("   #{idx}. #{inspect(part)}")
              end)
            else
              IO.puts("❌ No message in response")
            end

          {:error, error} ->
            IO.puts("❌ Zero-ceremony decode failed:")
            IO.inspect(error, pretty: true)
        end

        IO.puts("\n✨ Zero-ceremony API achieved!")
        IO.puts("📋 Response wrapped and decoded using provider protocol")

      {:error, error} ->
        IO.puts("❌ Raw request failed:")
        IO.inspect(error, pretty: true)
    end
  end

  defp test_context_based_generation do
    IO.puts("\n🎯 Testing context-based generation with raw Req...")

    # Create ReqLLM model with options
    {:ok, model} = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

    # Create context with system and user messages
    import ReqLLM.Context

    context =
      ReqLLM.Context.new([
        system("You are a helpful assistant that gives concise answers."),
        user("What is the capital of France? Answer in one word.")
      ])

    IO.puts("📨 Context has #{length(context.messages)} messages")

    # Manual Req setup with options
    base_request = Req.new(url: "/messages")

    attached_request =
      ReqLLM.Providers.Anthropic.attach(
        base_request,
        model,
        context: context,
        temperature: 0.1,
        max_tokens: 10
      )

    # Make the request
    case Req.request(attached_request, method: :post) do
      {:ok, response} ->
        IO.puts("✅ Context-based request successful!")
        IO.puts("📊 HTTP Status: #{response.status}")

        # Get raw JSON data and wrap it for proper decoding
        raw_data = response.body
        IO.puts("📄 Raw response data keys: #{inspect(Map.keys(raw_data))}")

        # Test direct decode using the provider's wrap_response function  
        IO.puts("🔄 Testing zero-ceremony direct decode with wrapped response...")

        wrapped_response = ReqLLM.Providers.Anthropic.wrap_response(raw_data)

        case ReqLLM.Response.decode_response(wrapped_response, model) do
          {:ok, decoded_response} ->
            IO.puts("✅ Response decoded!")
            IO.puts("📝 Response text: #{ReqLLM.Response.text(decoded_response)}")
            IO.puts("📊 Usage: #{inspect(ReqLLM.Response.usage(decoded_response))}")

            IO.puts(
              "🏁 Finish reason: #{inspect(ReqLLM.Response.finish_reason(decoded_response))}"
            )

          {:error, error} ->
            IO.puts("❌ Response decode failed:")
            IO.inspect(error, pretty: true)
        end

      {:error, error} ->
        IO.puts("❌ Context-based request failed:")
        IO.inspect(error, pretty: true)
    end
  end
end

# Run the demo
AnthropicDemo.run()
