defmodule ReqLLM.Coverage.OpenAI.ToolCallingTest do
  @moduledoc """
  OpenAI tool calling API feature coverage tests.

  Uses shared provider test macros to eliminate duplication while maintaining
  clear per-provider test organization and failure reporting.

  Run with LIVE=true to test against live API and capture fixtures.
  Otherwise uses cached fixtures for fast, reliable testing.
  """

  use ReqLLM.ProviderTest.ToolCalling,
    provider: :openai,
    model: "openai:gpt-4o-mini"
end
