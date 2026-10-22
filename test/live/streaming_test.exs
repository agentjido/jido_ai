defmodule Jido.AI.Live.StreamingTest do
  use Jido.AI.Test.LiveCase, async: false

  alias JidoAI.Examples.Streaming.Agent

  test "a real stream produces content and closes" do
    input = "Reply with the word streaming."

    {result, _trace} =
      capture_live(Agent, input, "streaming", fn ->
        with {:ok, response} <- Jido.AI.stream(Agent, input, live_options()) do
          try do
            {:ok, response |> ReqLLM.StreamResponse.tokens() |> Enum.join()}
          after
            ReqLLM.StreamResponse.close(response)
          end
        end
      end)

    assert {:ok, text} = result
    assert is_binary(text)
    assert String.trim(text) != ""
  end
end
