defmodule ReqLLM.Coverage.Anthropic.CoreTest do
  @moduledoc """
  Core Anthropic API feature coverage tests.

  Uses shared provider test macros to eliminate duplication while maintaining
  clear per-provider test organization and failure reporting.

  Run with LIVE=true to test against live API and capture fixtures.
  Otherwise uses cached fixtures for fast, reliable testing.
  """

  use ReqLLM.ProviderTest.Core,
    provider: :anthropic,
    model: "anthropic:claude-3-haiku-20240307"

  # Anthropic-specific tests
  alias ReqLLM.Test.LiveFixture, as: ReqFixture
  import ReqFixture

  test "temperature and sampling parameters" do
    result =
      use_fixture(:anthropic, "sampling_params", fn ->
        ReqLLM.generate_text(
          "anthropic:claude-3-haiku-20240307",
          "Count to 3",
          temperature: 0.0,
          top_p: 0.9,
          max_tokens: 10
        )
      end)

    {:ok, resp} = result
    text = ReqLLM.Response.text(resp)
    assert is_binary(text)
    assert text != ""
    assert resp.id != nil
  end

  test "stop sequences" do
    result =
      use_fixture(:anthropic, "stop_sequences", fn ->
        ReqLLM.generate_text(
          "anthropic:claude-3-haiku-20240307",
          "Count from 1 to 10, then say STOP",
          stop_sequences: ["STOP"],
          max_tokens: 50
        )
      end)

    {:ok, resp} = result
    text = ReqLLM.Response.text(resp)
    assert is_binary(text)
    assert text != ""
    assert resp.id != nil
    refute String.contains?(text, "STOP")
  end
end
