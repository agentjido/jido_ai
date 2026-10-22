defmodule Jido.AI.Reasoning.ReAct.PendingToolCallTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.ReAct.PendingToolCall

  test "complete/4 marks canonical ok triples as ok and preserves result" do
    call = %PendingToolCall{id: "call-1", name: "search", arguments: %{}}
    result = {:ok, %{result: "found"}, [:effect]}

    completed = PendingToolCall.complete(call, result, 2, 15)

    assert completed.status == :ok
    assert completed.result == result
    assert completed.attempts == 2
    assert completed.duration_ms == 15
  end

  test "complete/4 marks canonical error triples as error and preserves result" do
    call = %PendingToolCall{id: "call-1", name: "search", arguments: %{}}
    result = {:error, %{type: :failed}, []}

    completed = PendingToolCall.complete(call, result, 0, 15)

    assert completed.status == :error
    assert completed.result == result
    assert completed.attempts == 1
    assert completed.duration_ms == 15
  end
end
