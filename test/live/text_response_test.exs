defmodule Jido.AI.Live.TextResponseTest do
  use Jido.AI.Test.LiveCase, async: false

  alias JidoAI.Examples.BasicAgent.Agent

  test "a real model returns text through the Jido AI response path" do
    input = "Reply with the word pong."

    {result, _trace} =
      capture_live(Agent, input, "text_response", fn ->
        Jido.AI.reason(Agent, input, live_options())
      end)

    assert {:ok, reasoning} = result
    assert is_binary(reasoning.output)
    assert String.trim(reasoning.output) != ""
    assert %{model_calls: 1, tool_calls: 0, iterations: 0} = reasoning.usage
  end
end
