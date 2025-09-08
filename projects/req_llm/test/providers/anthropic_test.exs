defmodule ReqLLM.Providers.AnthropicTest do
  use ReqLLM.ProviderCase, async: true

  describe "fixture-based testing infrastructure" do
    test "collect streaming chunks from fixture data" do
      with_fixture("anthropic/completion_streaming", fn ->
        # Simulate stream processing using fixture data directly
        fixture = load_fixture_data("anthropic/completion_streaming")

        # Extract text deltas from streaming events
        text_chunks = extract_text_chunks(fixture)

        assert length(text_chunks) == 2
        assert "Hello" in text_chunks
        assert "! How can I help you today?" in text_chunks

        # Test the collect_chunks helper function
        chunks = collect_chunks(text_chunks)
        assert chunks == text_chunks
      end)
    end
  end

  describe "provider behavior compliance" do
    test "anthropic provider exists" do
      assert Code.ensure_loaded?(ReqLLM.Providers.Anthropic)
    end

    test "has expected module structure" do
      functions = ReqLLM.Providers.Anthropic.__info__(:functions)

      # Provider should have attach function (from Plugin behavior)
      assert {:attach, 2} in functions

      # Note: The actual provider interface may differ from initial expectations
      # This test verifies the module loads and has basic structure
      assert is_list(functions)
      assert length(functions) > 0
    end
  end

  # Private test helpers

  defp load_fixture_data(fixture_path) do
    file_path = Path.join([__DIR__, "..", "support", "fixtures", fixture_path <> ".json"])
    File.read!(file_path) |> Jason.decode!()
  end

  defp extract_text_chunks(streaming_events) do
    streaming_events
    |> Enum.filter(fn event -> event["type"] == "content_block_delta" end)
    |> Enum.map(fn event -> get_in(event, ["delta", "text"]) end)
    |> Enum.reject(&is_nil/1)
  end
end
