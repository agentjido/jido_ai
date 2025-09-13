defmodule ReqLLM.Coverage.Groq.StreamingTest do
  @moduledoc """
  Groq streaming API feature coverage tests.

  Uses shared provider test macros to eliminate duplication while maintaining
  clear per-provider test organization and failure reporting.

  Run with LIVE=true to test against live API and capture fixtures.
  Otherwise uses cached fixtures for fast, reliable testing.
  """

  use ReqLLM.ProviderTest.Streaming,
    provider: :groq,
    model: "groq:llama-3.1-8b-instant"
end
