defmodule Jido.AI.Session.Change do
  @moduledoc false
  use Jido.Agent.Directive

  @schema Zoi.struct(
            __MODULE__,
            %{
              operation: Zoi.enum([:start, :finish, :control, :history, :progress]),
              record: Jido.AI.Session.Record.schema(),
              batch_id: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil)
            },
            coerce: true
          )
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
end
