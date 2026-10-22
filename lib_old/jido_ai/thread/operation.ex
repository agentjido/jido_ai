defmodule Jido.AI.Thread.Operation do
  @moduledoc false
  alias Jido.Thread

  def valid?(%{op_id: id, context_ref: ref, operation: operation}) when is_map(operation) do
    nonempty?(id) and nonempty?(ref) and operation[:type] in [:replace, :switch] and
      operation[:reason] in [:manual, :restore, :compaction, :system] and
      (is_nil(operation[:base_seq]) or is_integer(operation[:base_seq])) and
      is_map(operation[:meta]) and
      case operation.type do
        :replace -> match?({:ok, _}, Thread.validate(operation[:result_context]))
        :switch -> is_nil(operation[:result_context])
      end
  end

  def valid?(_), do: false

  def decode(%Thread.Entry{kind: kind, payload: %{"version" => 1} = payload})
      when kind in [:ai_context_operation, "ai_context_operation"] do
    raw = payload["operation"]
    type = enum(raw["type"], [:replace, :switch])
    true = type != :switch or is_nil(raw["result_context"])

    result =
      if type == :replace do
        {:ok, thread} = Thread.decode(raw["result_context"])
        thread
      end

    value = %{
      op_id: payload["op_id"],
      context_ref: payload["context_ref"],
      operation: %{
        type: type,
        reason: enum(raw["reason"], [:manual, :restore, :compaction, :system]),
        result_context: result,
        base_seq: raw["base_seq"],
        meta: raw["meta"]
      }
    }

    if valid?(value), do: {:ok, value}, else: {:error, :invalid_context_operation}
  rescue
    _ -> {:error, :invalid_context_operation}
  end

  def decode(_), do: {:error, :invalid_context_operation}

  def encode(value) do
    operation = value.operation

    %{
      "version" => 1,
      "op_id" => value.op_id,
      "context_ref" => value.context_ref,
      "operation" => %{
        "type" => Atom.to_string(operation.type),
        "reason" => Atom.to_string(operation.reason),
        "result_context" => if(operation.result_context, do: Thread.encode(operation.result_context)),
        "base_seq" => operation.base_seq,
        "meta" => operation.meta
      }
    }
  end

  defp enum(value, values), do: Enum.find(values, &(value == &1 or value == Atom.to_string(&1)))
  defp nonempty?(value), do: is_binary(value) and value != ""
end
