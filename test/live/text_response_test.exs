defmodule Jido.AI.Live.TextResponseTest do
  use Jido.AI.Test.LiveCase, async: false

  alias JidoAI.Examples.BasicAgent.Agent

  test "a real model returns text through the Jido AI response path" do
    input = "Reply with the word pong."

    {result, _trace} =
      capture_live(Agent, input, "text_response", fn ->
        Jido.AI.generate(Agent, input, live_options())
      end)

    assert {:ok, text} = result
    assert is_binary(text)
    assert String.trim(text) != ""
  end
end
