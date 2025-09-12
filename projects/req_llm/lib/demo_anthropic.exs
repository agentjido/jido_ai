#!/usr/bin/env mix run
# Demo script to test the Anthropic provider with direct Req access
# Run with: mix run demo_anthropic.exs

require Logger

defmodule AnthropicDemo do
  @moduledoc """
  Demo script to test the Anthropic provider using direct Req access.
  This script tests the attach/3 method and includes extensive debugging.
  """

  def run do
    IO.puts("=== ReqLLM Anthropic Provider Demo ===\n")

    # Check if we have an API key set
    api_key = JidoKeys.get("ANTHROPIC_API_KEY")

    if !api_key || api_key == "" do
      IO.puts("❌ Error: ANTHROPIC_API_KEY not found in JidoKeys")
      IO.puts("Please run: iex -S mix")
      IO.puts("Then: JidoKeys.put(\"ANTHROPIC_API_KEY\", \"your-key-here\")")
      exit(:normal)
    end

    IO.puts("✅ API key found (length: #{String.length(api_key)})")

    # Create a simple test model - using the cheapest Claude model
    model_string = "anthropic:claude-3-haiku-20240307"
    IO.puts("🎯 Testing with model: #{model_string}")

    # Parse the model
    model = ReqLLM.Model.from!(model_string)
    IO.puts("📋 Parsed model:")
    IO.inspect(model, pretty: true, limit: :infinity)

    # Create proper ReqLLM context with messages
    import ReqLLM.Context

    context =
      ReqLLM.Context.new([
        user("Say hello in exactly 3 words")
      ])

    IO.puts("\n📨 Test context:")
    IO.inspect(context, pretty: true, limit: :infinity)

    IO.puts("\n📋 Context messages structure:")

    context.messages
    |> Enum.each(fn msg ->
      IO.puts("  Role: #{msg.role}")
      IO.puts("  Content parts:")

      msg.content
      |> Enum.each(fn part ->
        IO.puts("    Type: #{part.type}, Text: #{inspect(part.text)}")
      end)
    end)

    # Create the base Req request
    base_request = Req.new(url: "/messages")
    IO.puts("\n🔧 Base Req request:")
    IO.inspect(base_request, pretty: true, limit: :infinity)

    # Test options - pass the context instead of raw messages
    # Note: using :stream instead of :stream? to match the provider expectations
    test_opts = [
      context: context,
      temperature: 0.3,
      max_tokens: 50,
      stream: false
    ]

    IO.puts("\n⚙️  Test options:")
    IO.inspect(test_opts, pretty: true)

    # Attach the Anthropic provider
    IO.puts("\n🔗 Attaching Anthropic provider...")

    try do
      attached_request = ReqLLM.Providers.Anthropic.attach(base_request, model, test_opts)

      IO.puts("✅ Successfully attached provider")
      IO.puts("\n📋 Attached request structure:")
      IO.inspect(attached_request, pretty: true, limit: :infinity)

      IO.puts("\n🌐 Request options after attach:")
      IO.inspect(attached_request.options, pretty: true, limit: :infinity)

      IO.puts("\n🔍 Temperature debugging:")
      IO.puts("  Temperature in options: #{inspect(attached_request.options[:temperature])}")
      IO.puts("  Max tokens in options: #{inspect(attached_request.options[:max_tokens])}")

      IO.puts("\n📡 Request headers after attach:")
      IO.inspect(attached_request.headers, pretty: true)

      # Make the actual API call
      IO.puts("\n🚀 Making API call...")

      case Req.request(attached_request, method: :post) do
        {:ok, response} ->
          IO.puts("✅ API call successful!")
          IO.puts("\n📊 Response status: #{response.status}")
          IO.puts("📋 Response headers:")
          IO.inspect(response.headers, pretty: true)

          IO.puts("\n📦 Raw response body:")
          IO.inspect(response.body, pretty: true, limit: :infinity)

          # Test the codec if we got a successful response
          if response.status == 200 do
            IO.puts("\n🔍 Testing codec decode...")
            test_codec_decode(response.body, context)
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

  defp test_codec_decode(body, original_context) when is_map(body) do
    try do
      # Show the original context we sent
      IO.puts("📤 Original context sent:")
      IO.inspect(original_context, pretty: true, limit: :infinity)

      # Create the provider struct with the response context
      provider_struct = %ReqLLM.Providers.Anthropic{context: body}

      IO.puts("\n🔍 Provider struct for codec:")
      IO.inspect(provider_struct, pretty: true, limit: :infinity)

      # Test the codec decode
      decoded = ReqLLM.Context.Codec.decode(provider_struct)

      IO.puts("\n✅ Codec decode successful!")
      IO.puts("📝 Decoded chunks:")
      IO.inspect(decoded, pretty: true, limit: :infinity)

      # Show chunk details
      if is_list(decoded) do
        IO.puts("\n🔬 Chunk analysis:")

        decoded
        |> Enum.with_index()
        |> Enum.each(fn {chunk, idx} ->
          IO.puts("  Chunk #{idx}: #{chunk.__struct__}")

          case chunk do
            %ReqLLM.StreamChunk{type: :content, text: text} ->
              IO.puts("    Text: #{inspect(text)}")

            %ReqLLM.StreamChunk{type: :tool_call, name: name, arguments: args} ->
              IO.puts("    Tool: #{name}, Args: #{inspect(args)}")

            %ReqLLM.StreamChunk{type: :thinking, text: text} ->
              IO.puts("    Thinking: #{inspect(text)}")

            other ->
              IO.puts("    Other: #{inspect(other)}")
          end
        end)
      end
    rescue
      error ->
        IO.puts("❌ Error during codec decode:")
        IO.inspect(error, pretty: true, limit: :infinity)
        IO.puts("\nStacktrace:")
        IO.puts(Exception.format_stacktrace(__STACKTRACE__))
    end
  end

  defp test_codec_decode(body, _context) do
    IO.puts("⚠️  Response body is not a map, cannot test codec decode")
    IO.puts("Body type: #{inspect(body.__struct__ || :unknown)}")
  end
end

# Run the demo
AnthropicDemo.run()
