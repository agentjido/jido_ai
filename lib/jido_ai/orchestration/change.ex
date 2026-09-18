defmodule Jido.AI.Orchestration.Change do
  @moduledoc false
  @schema Zoi.struct(
            __MODULE__,
            %{
              operation: Zoi.enum([:start, :finish, :control, :history, :progress]),
              record: Jido.AI.Request.Record.schema(),
              batch_id: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil)
            },
            coerce: true
          )
  defstruct Zoi.Struct.struct_fields(@schema)
  use Jido.Agent.Directive
  def schema, do: @schema
end
