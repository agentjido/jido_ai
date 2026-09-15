defmodule Jido.AI.Orchestration.DeliveryReceipt do
  @moduledoc false
  use Jido.Agent.Directive

  @schema Zoi.struct(
            __MODULE__,
            %{batch_id: Zoi.string(), ticket: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil)},
            coerce: true
          )
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
end
