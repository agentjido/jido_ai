defmodule ReqLLM.Coverage.OpenRouter.CoreTest do
  @moduledoc """
  Core OpenRouter API feature coverage tests.

  Uses shared provider test macros to eliminate duplication while maintaining
  clear per-provider test organization and failure reporting.

  Run with LIVE=true to test against live API and capture fixtures.
  Otherwise uses cached fixtures for fast, reliable testing.
  """

  use ReqLLM.ProviderTest.Core,
    provider: :openrouter,
    model: "openrouter:anthropic/claude-3-haiku"

  # OpenRouter-specific tests can be added here
  # For example: model routing, provider preferences, transforms, etc.

  describe "OpenRouter-specific parameters" do
    test "frequency_penalty parameter" do
      result =
        use_fixture(:openrouter, "frequency_penalty_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Repeat the word 'hello' five times")])

          ReqLLM.generate_text("openrouter:anthropic/claude-3-haiku", ctx,
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
        use_fixture(:openrouter, "presence_penalty_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Write about cats and dogs")])

          ReqLLM.generate_text("openrouter:anthropic/claude-3-haiku", ctx,
            max_tokens: 50,
            temperature: 0.7,
            # Encourage diverse vocabulary
            presence_penalty: 0.5
          )
        end)

      {:ok, resp} = result
      assert resp.message.content |> Enum.at(0) |> Map.get(:text) =~ ~r/cat|dog/i
    end

    test "top_k parameter" do
      result =
        use_fixture(:openrouter, "top_k_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Say hello")])

          ReqLLM.generate_text("openrouter:anthropic/claude-3-haiku", ctx,
            max_tokens: 10,
            temperature: 0.7,
            # Limit vocabulary choices
            top_k: 10
          )
        end)

      {:ok, resp} = result
      assert resp.message.content |> Enum.at(0) |> Map.get(:text) =~ ~r/hello|hi/i
    end

    test "min_p parameter" do
      result =
        use_fixture(:openrouter, "min_p_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Say hello")])

          ReqLLM.generate_text("openrouter:anthropic/claude-3-haiku", ctx,
            max_tokens: 10,
            temperature: 0.7,
            # Set minimum probability threshold
            min_p: 0.1
          )
        end)

      {:ok, resp} = result
      assert resp.message.content |> Enum.at(0) |> Map.get(:text) =~ ~r/hello|hi/i
    end

    test "user parameter for tracking" do
      result =
        use_fixture(:openrouter, "user_parameter_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Say hello")])

          ReqLLM.generate_text("openrouter:anthropic/claude-3-haiku", ctx,
            max_tokens: 10,
            temperature: 0.7,
            # User identifier for abuse detection
            user: "test-user-123"
          )
        end)

      {:ok, resp} = result
      assert resp.message.content |> Enum.at(0) |> Map.get(:text) =~ ~r/hello|hi/i
    end
  end
end
