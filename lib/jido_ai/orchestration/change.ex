defmodule Jido.AI.Orchestration.Change do
  @moduledoc false
  use Jido.Agent.Directive

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
  def schema, do: @schema
end
