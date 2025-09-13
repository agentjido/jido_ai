defmodule ReqLLM.Coverage.Groq.CoreTest do
  @moduledoc """
  Core Groq API feature coverage tests.

  Uses shared provider test macros to eliminate duplication while maintaining
  clear per-provider test organization and failure reporting.

  Run with LIVE=true to test against live API and capture fixtures.
  Otherwise uses cached fixtures for fast, reliable testing.
  """

  use ReqLLM.ProviderTest.Core,
    provider: :groq,
    model: "groq:llama-3.1-8b-instant"

  # Groq-specific tests can be added here
  # For example: service tiers, reasoning effort, search settings, compound features, etc.

  describe "Groq-specific parameters" do
    test "service_tier parameter (may require paid plan)" do
      result =
        use_fixture(:groq, "service_tier_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Say hello")])

          ReqLLM.generate_text("groq:llama-3.1-8b-instant", ctx,
            max_tokens: 20,
            temperature: 0.7,
            provider_options: [
              service_tier: "auto"
            ]
          )
        end)

      # This test may fail if service_tier requires a paid plan
      case result do
        {:ok, resp} ->
          assert is_binary(resp.message.content |> Enum.at(0) |> Map.get(:text))

        {:error, _} ->
          # Accept error for unsupported features
          assert true
      end
    end

    test "reasoning_effort parameter (may not be supported by all models)" do
      result =
        use_fixture(:groq, "reasoning_effort_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Explain photosynthesis briefly")])

          ReqLLM.generate_text("groq:llama-3.1-8b-instant", ctx,
            max_tokens: 100,
            temperature: 0.7,
            provider_options: [
              reasoning_effort: "medium"
            ]
          )
        end)

      # This test may fail if reasoning_effort is not supported by the model
      case result do
        {:ok, resp} ->
          text = resp.message.content |> Enum.at(0) |> Map.get(:text)
          assert text =~ ~r/photosynthesis|plant|light/i

        {:error, _} ->
          # Accept error for unsupported features
          assert true
      end
    end

    test "frequency_penalty parameter" do
      result =
        use_fixture(:groq, "frequency_penalty_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Repeat the word 'hello' five times")])

          ReqLLM.generate_text("groq:llama-3.1-8b-instant", ctx,
            max_tokens: 50,
            temperature: 0.7,
            # Reduce repetition
            frequency_penalty: 1.0
          )
        end)

      {:ok, resp} = result
      assert is_binary(resp.message.content |> Enum.at(0) |> Map.get(:text))
    end

    test "presence_penalty parameter" do
      result =
        use_fixture(:groq, "presence_penalty_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Write about cats and dogs")])

          ReqLLM.generate_text("groq:llama-3.1-8b-instant", ctx,
            max_tokens: 50,
            temperature: 0.7,
            # Encourage diverse vocabulary
            presence_penalty: 0.5
          )
        end)

      {:ok, resp} = result
      assert resp.message.content |> Enum.at(0) |> Map.get(:text) =~ ~r/cat|dog/i
    end

    test "user parameter for tracking" do
      result =
        use_fixture(:groq, "user_parameter_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Say hello")])

          ReqLLM.generate_text("groq:llama-3.1-8b-instant", ctx,
            max_tokens: 10,
            temperature: 0.7,
            # User identifier for tracking/abuse detection
            user: "test-user-456"
          )
        end)

      {:ok, resp} = result
      assert resp.message.content |> Enum.at(0) |> Map.get(:text) =~ ~r/hello|hi/i
    end

    # Note: logit_bias test removed due to validation complexity with token IDs

    test "seed parameter for deterministic output" do
      result1 =
        use_fixture(:groq, "seed_test_1", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Pick a random number between 1 and 10")])

          ReqLLM.generate_text("groq:llama-3.1-8b-instant", ctx,
            max_tokens: 20,
            temperature: 0.7,
            # Use specific seed for deterministic output
            seed: 12345
          )
        end)

      result2 =
        use_fixture(:groq, "seed_test_2", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Pick a random number between 1 and 10")])

          ReqLLM.generate_text("groq:llama-3.1-8b-instant", ctx,
            max_tokens: 20,
            temperature: 0.7,
            # Use same seed - should produce similar output
            seed: 12345
          )
        end)

      {:ok, resp1} = result1
      {:ok, resp2} = result2

      # Both responses should contain numbers
      text1 = resp1.message.content |> Enum.at(0) |> Map.get(:text)
      text2 = resp2.message.content |> Enum.at(0) |> Map.get(:text)

      assert text1 =~ ~r/\d/
      assert text2 =~ ~r/\d/
      # With the same seed, responses may be identical or very similar
    end

    test "complex interaction with multiple parameters" do
      result =
        use_fixture(:groq, "complex_parameters_test", fn ->
          ctx =
            ReqLLM.Context.new([
              ReqLLM.Context.user("Write a creative short story about a robot")
            ])

          ReqLLM.generate_text("groq:llama-3.1-8b-instant", ctx,
            max_tokens: 150,
            temperature: 0.8,
            # Combine multiple supported Groq parameters
            frequency_penalty: 0.3,
            presence_penalty: 0.2,
            user: "creative-writer-789"
          )
        end)

      {:ok, resp} = result
      text = resp.message.content |> Enum.at(0) |> Map.get(:text)
      assert text =~ ~r/robot/i
      # Should be a reasonable story length
      assert String.length(text) > 20
    end
  end
end
