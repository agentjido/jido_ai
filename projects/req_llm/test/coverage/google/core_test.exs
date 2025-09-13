defmodule ReqLLM.Coverage.Google.CoreTest do
  @moduledoc """
  Core Google Gemini API feature coverage tests.

  Uses shared provider test macros to eliminate duplication while maintaining
  clear per-provider test organization and failure reporting.

  Run with LIVE=true to test against live API and capture fixtures.
  Otherwise uses cached fixtures for fast, reliable testing.
  """

  use ReqLLM.ProviderTest.Core,
    provider: :google,
    model: "google:gemini-1.5-flash"

  # Google-specific tests can be added here
  # For example: safety settings, candidate_count, multi-modal inputs, etc.

  describe "Google-specific parameters" do
    test "candidate_count parameter" do
      result =
        use_fixture(:google, "candidate_count_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Generate 3 different greetings")])

          ReqLLM.generate_text("google:gemini-1.5-flash", ctx,
            max_tokens: 20,
            temperature: 0.9,
            # Google supports 1-8 candidates
            candidate_count: 1
          )
        end)

      {:ok, resp} = result
      assert resp.message.content |> Enum.at(0) |> Map.get(:text) =~ ~r/hello|hi|greetings/i
    end

    test "top_k parameter" do
      result =
        use_fixture(:google, "top_k_test", fn ->
          ctx = ReqLLM.Context.new([ReqLLM.Context.user("Say hello")])

          ReqLLM.generate_text("google:gemini-1.5-flash", ctx,
            max_tokens: 10,
            temperature: 0.7,
            # Google supports top_k >= 1
            top_k: 40
          )
        end)

      {:ok, resp} = result
      assert resp.message.content |> Enum.at(0) |> Map.get(:text) =~ ~r/hello|hi/i
    end
  end
end
