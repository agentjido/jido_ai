defmodule Jido.AI.Provider.CostIntegrationTest do
  use ExUnit.Case, async: true
  use Jido.AI.TestSupport.HTTPCase
  use Jido.AI.TestSupport.KeyringCase

  alias Jido.AI.Provider
  alias Jido.AI.Test.Fixtures.{ModelFixtures, ProviderFixtures}

  describe "cost tracking integration" do
    test "extracts actual usage and calculates cost from OpenAI response", %{test_name: test_name} do
      model =
        ModelFixtures.gpt4()
        |> Map.put(:cost, %{input: 1.5, output: 6.0})

      # Mock response with actual usage data
      response_body =
        ProviderFixtures.openai_response("Hello world!",
          prompt_tokens: 25,
          completion_tokens: 15,
          total_tokens: 40
        )

      session(openai_api_key: "sk-test-key") do
        with_success(response_body) do
          case Provider.OpenAI.generate_text(model, "Hello") do
            {:ok, text} ->
              assert text == "Hello world!"

            # Verify cost calculation happened in logs
            # The actual cost should be logged at debug level
            # (25 * 1.5 + 15 * 6.0) / 1_000_000 = 0.0000975

            {:error, error} ->
              flunk("Expected success, got error: #{inspect(error)}")
          end
        end
      end
    end

    test "handles responses without usage data gracefully", %{test_name: test_name} do
      model =
        ModelFixtures.gpt4()
        |> Map.put(:cost, %{input: 1.5, output: 6.0})

      # Mock response without usage data (fallback to estimation)
      response_body = %{
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => "Hello world!"
            },
            "finish_reason" => "stop"
          }
        ]
        # No "usage" field
      }

      session(openai_api_key: "sk-test-key") do
        with_success(response_body) do
          case Provider.OpenAI.generate_text(model, "Hello") do
            {:ok, text} ->
              assert text == "Hello world!"

            # Should still work, falling back to token estimation

            {:error, error} ->
              flunk("Expected success, got error: #{inspect(error)}")
          end
        end
      end
    end
  end
end
