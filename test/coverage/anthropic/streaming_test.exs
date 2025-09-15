defmodule ReqLLM.Coverage.Anthropic.StreamingTest do
  @moduledoc """
  Anthropic streaming API feature coverage tests.

  Uses shared provider test macros to eliminate duplication while maintaining
  clear per-provider test organization and failure reporting.

  Run with LIVE=true to test against live API and capture fixtures.
  Otherwise uses cached fixtures for fast, reliable testing.
  """

  use ReqLLM.ProviderTest.Streaming,
    provider: :anthropic,
    model: "anthropic:claude-3-haiku-20240307"
end
