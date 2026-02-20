defmodule Jido.AI.SignalSurfaceTest do
  use ExUnit.Case, async: true

  test "deprecated signal modules are removed" do
    refute Code.ensure_loaded?(Jido.AI.Signal.LLMRequest)
    refute Code.ensure_loaded?(Jido.AI.Signal.EmbedRequest)
    refute Code.ensure_loaded?(Jido.AI.Signal.LLMCancelled)
    refute Code.ensure_loaded?(Jido.AI.Signal.ToolCall)
    refute Code.ensure_loaded?(Jido.AI.Signal.LLMError)
    refute Code.ensure_loaded?(Jido.AI.Signal.EmbedError)
    refute Code.ensure_loaded?(Jido.AI.Signal.ToolError)
    refute Code.ensure_loaded?(Jido.AI.Signal.Step)
  end

  test "canonical signal modules remain available" do
    assert Code.ensure_loaded?(Jido.AI.Signal.RequestStarted)
    assert Code.ensure_loaded?(Jido.AI.Signal.RequestCompleted)
    assert Code.ensure_loaded?(Jido.AI.Signal.RequestFailed)
    assert Code.ensure_loaded?(Jido.AI.Signal.RequestError)
    assert Code.ensure_loaded?(Jido.AI.Signal.LLMResponse)
    assert Code.ensure_loaded?(Jido.AI.Signal.LLMDelta)
    assert Code.ensure_loaded?(Jido.AI.Signal.ToolResult)
    assert Code.ensure_loaded?(Jido.AI.Signal.EmbedResult)
    assert Code.ensure_loaded?(Jido.AI.Signal.Usage)
  end
end
