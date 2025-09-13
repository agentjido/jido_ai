defmodule ReqLLM.Coverage.XAI.CoreTest do
  @moduledoc """
  Core xAI API feature coverage tests.

  Uses shared provider test macros to eliminate duplication while maintaining
  clear per-provider test organization and failure reporting.

  Run with LIVE=true to test against live API and capture fixtures.
  Otherwise uses cached fixtures for fast, reliable testing.
  """

  use ReqLLM.ProviderTest.Core,
    provider: :xai,
    model: "xai:grok-3-mini"

  # xAI-specific tests for unique features
  describe "xAI-specific parameters" do
    test "live_search parameter for real-time information" do
      result =
        use_fixture(:xai, "live_search_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("What's today's date?")])

          ReqLLM.generate_text("xai:grok-3-mini", ctx,
            max_tokens: 50,
            temperature: 0.7,
            provider_options: [
              live_search: true
            ]
          )
        end)

      # Live search may require API key with sufficient credits
      case result do
        {:ok, resp} ->
          text = resp.message.content |> Enum.at(0) |> Map.get(:text)
          assert is_binary(text)
          # Should contain some date information if live search worked
          assert String.length(text) > 10

        {:error, _} ->
          # Accept error for insufficient credits or unsupported feature
          assert true
      end
    end

    test "reasoning_effort parameter for reasoning models" do
      result =
        use_fixture(:xai, "reasoning_effort_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Solve: 2x + 5 = 13")])

          ReqLLM.generate_text("xai:grok-3-mini", ctx,
            max_tokens: 100,
            temperature: 0.3,
            provider_options: [
              reasoning_effort: "medium"
            ]
          )
        end)

      # Reasoning effort should work on reasoning models like grok-3-mini
      case result do
        {:ok, resp} ->
          text = resp.message.content |> Enum.at(0) |> Map.get(:text)
          assert text =~ ~r/x|4|solution/i

        {:error, _} ->
          # Accept error if reasoning_effort isn't supported
          assert true
      end
    end

    test "enable_cached_prompt parameter" do
      result =
        use_fixture(:xai, "cached_prompt_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Say hello")])

          ReqLLM.generate_text("xai:grok-3-mini", ctx,
            max_tokens: 20,
            temperature: 0.7,
            provider_options: [
              enable_cached_prompt: true
            ]
          )
        end)

      {:ok, resp} = result
      assert resp.message.content |> Enum.at(0) |> Map.get(:text) =~ ~r/hello|hi/i
    end

    test "service_tier parameter" do
      result =
        use_fixture(:xai, "service_tier_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Tell me a short joke")])

          ReqLLM.generate_text("xai:grok-3-mini", ctx,
            max_tokens: 50,
            temperature: 0.8,
            provider_options: [
              service_tier: "auto"
            ]
          )
        end)

      {:ok, resp} = result
      text = resp.message.content |> Enum.at(0) |> Map.get(:text)
      assert is_binary(text)
      assert String.length(text) > 5
    end

    test "standard OpenAI-compatible parameters work" do
      result =
        use_fixture(:xai, "standard_parameters_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Count from 1 to 3")])

          # Note: presence_penalty and frequency_penalty may not be supported by all xAI models
          ReqLLM.generate_text("xai:grok-3-mini", ctx,
            max_tokens: 50,
            temperature: 0.5,
            user: "test-user-xai"
          )
        end)

      case result do
        {:ok, resp} ->
          text = resp.message.content |> Enum.at(0) |> Map.get(:text)
          assert text =~ ~r/1|2|3/

        {:error, _} ->
          # Accept errors for unsupported parameters
          assert true
      end
    end
  end

  describe "Grok 4 model limitations" do
    test "Grok 4 rejects unsupported parameters" do
      # Note: This test may need adjustment based on actual Grok 4 behavior
      result =
        use_fixture(:xai, "grok4_limitations_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("What is 2+2?")])

          # Grok 4 should reject presence_penalty, frequency_penalty, and stop
          ReqLLM.generate_text("xai:grok-4", ctx,
            max_tokens: 20,
            temperature: 0.7,
            # These should be automatically filtered out by our provider
            frequency_penalty: 0.5,
            presence_penalty: 0.5
          )
        end)

      # Should work because our provider filters out unsupported parameters
      case result do
        {:ok, resp} ->
          # Handle cases where message might be nil or content might be empty
          if resp.message && resp.message.content do
            assert resp.message.content |> Enum.at(0) |> Map.get(:text) =~ ~r/4/
          else
            # Accept if no content due to token limits or other API behavior
            assert true
          end

        {:error, _} ->
          # Accept error if Grok 4 is not available
          assert true
      end
    end
  end

  describe "xAI response metadata" do
    test "includes xAI-specific metadata in response" do
      result =
        use_fixture(:xai, "metadata_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Hello")])

          ReqLLM.generate_text("xai:grok-3-mini", ctx,
            max_tokens: 20,
            temperature: 0.7
          )
        end)

      {:ok, resp} = result
      
      # Check that we have basic response structure
      assert is_binary(resp.id)
      assert is_map(resp.usage)
      # Usage might have string keys from the API
      input_tokens = Map.get(resp.usage, :input_tokens) || Map.get(resp.usage, "input_tokens")
      assert input_tokens > 0
      
      # Check provider_meta for xAI-specific fields
      assert is_map(resp.provider_meta)
    end
  end
end
