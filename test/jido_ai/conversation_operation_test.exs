defmodule Jido.AI.ConversationOperationTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Thread.Operation
  alias Jido.Thread

  test "operation payload round trips with a canonical snapshot" do
    value = value(:replace, Thread.new())
    payload = value |> Operation.encode() |> Jason.encode!() |> Jason.decode!()
    entry = Thread.Entry.new(kind: :ai_context_operation, payload: payload)
    assert {:ok, restored} = Operation.decode(entry)
    assert restored == value
  end

  test "invalid saved operations fail with a tagged error" do
    payload = Operation.encode(value(:switch, nil))

    for invalid <- [
          Map.put(payload, "version", 99),
          Map.put(payload, "op_id", ""),
          Map.put(payload, "context_ref", nil),
          put_in(payload, ["operation", "type"], "unknown"),
          put_in(payload, ["operation", "result_context"], Thread.encode(Thread.new())),
          put_in(payload, ["operation", "meta"], []),
          Map.put(payload, "operation", nil)
        ] do
      entry = Thread.Entry.new(kind: :ai_context_operation, payload: invalid)
      assert {:error, :invalid_context_operation} = Operation.decode(entry)
    end
  end

  defp value(type, result) do
    %{
      op_id: "operation",
      context_ref: "default",
      operation: %{type: type, reason: :manual, result_context: result, base_seq: nil, meta: %{}}
    }
  end
end
