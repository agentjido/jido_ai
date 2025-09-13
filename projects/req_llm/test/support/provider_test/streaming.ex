defmodule ReqLLM.ProviderTest.Streaming do
  @moduledoc """
  Streaming text generation tests.

  Tests stream-based generation features:
  - Basic streaming with text chunks
  - Stream interruption and error handling
  - Chunk validation and parsing
  - Stream completion and termination
  """

  defmacro __using__(opts) do
    provider = Keyword.fetch!(opts, :provider)
    model = Keyword.fetch!(opts, :model)

    quote bind_quoted: [provider: provider, model: model] do
      use ExUnit.Case, async: false

      alias ReqLLM.Test.LiveFixture, as: ReqFixture
      import ReqFixture

      @moduletag :coverage
      @moduletag provider

      describe "streaming text generation" do
        test "basic streaming completion returns chunks" do
          {:ok, response} =
            use_fixture(unquote(provider), "basic_streaming", fn ->
              ReqLLM.stream_text(unquote(model), "Hello world!", max_tokens: 20)
            end)

          if ReqLLM.Test.LiveFixture.live_mode?() do
            # Live mode: test streaming behavior
            assert response.stream?

            # Collect all chunks
            chunks = Enum.to_list(response.stream)

            # Basic validations
            assert is_list(chunks)
            assert length(chunks) > 0

            # Verify chunks are proper StreamChunk structs
            assert Enum.all?(chunks, fn chunk ->
              match?(%ReqLLM.StreamChunk{}, chunk)
            end)

            # Verify at least one chunk has text content (including thinking for reasoning models)
            assert Enum.any?(chunks, fn chunk ->
              chunk.type in [:text, :content, :thinking] and is_binary(chunk.text) and chunk.text != ""
            end)

            # Verify response has final message when joined
            {:ok, joined_response} = ReqLLM.Response.join_stream(response)
            assert joined_response.message
            assert joined_response.message.content
          else
            # Cached mode: response was materialized, test final result
            assert response.message
            assert response.message.content
            
            # Verify we have some content (may be empty for thinking-only responses)
            text = ReqLLM.Response.text(response)
            assert is_binary(text)
          end
        end
      end
    end
  end
end
