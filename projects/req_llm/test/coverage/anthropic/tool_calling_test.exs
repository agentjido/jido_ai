defmodule ReqLLM.Coverage.Anthropic.ToolCallingTest do
  @moduledoc """
  Anthropic tool calling API feature coverage tests.

  Uses shared provider test macros to eliminate duplication while maintaining
  clear per-provider test organization and failure reporting.

  Run with LIVE=true to test against live API and capture fixtures.
  Otherwise uses cached fixtures for fast, reliable testing.
  """

  use ReqLLM.ProviderTest.ToolCalling,
    provider: :anthropic,
    model: "anthropic:claude-3-5-sonnet-20241022"
end
