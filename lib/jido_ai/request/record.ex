defmodule Jido.AI.Request.Record do
  @moduledoc false
  @schema Zoi.object(
            %{
              id: Zoi.string() |> Zoi.min(1),
              run_id: Zoi.string() |> Zoi.min(1),
              session_id: Zoi.string() |> Zoi.min(1) |> Zoi.nullable() |> Zoi.default(nil),
              profile_id: Zoi.atom(),
              method: Zoi.atom() |> Zoi.default(:react),
              query: Jido.AI.Query.schema(),
              status: Zoi.enum([:pending, :completed, :failed]),
              result: Zoi.any() |> Zoi.default(nil),
              content: Zoi.string() |> Zoi.default(""),
              value: Zoi.any() |> Zoi.default(nil),
              error: Zoi.any() |> Zoi.default(nil),
              inserted_at: Zoi.integer(),
              completed_at: Zoi.integer() |> Zoi.nullable(),
              streamed: Zoi.boolean(),
              streaming: Zoi.boolean() |> Zoi.default(false),
              max_retained_requests: Zoi.integer() |> Zoi.min(1),
              extra_refs: Zoi.map() |> Zoi.default(%{}),
              meta: Zoi.map() |> Zoi.default(%{}),
              inspection: Zoi.map() |> Zoi.default(%{}),
              completion_reserve: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
              last_control: Zoi.map() |> Zoi.nullable() |> Zoi.default(nil)
            },
            unrecognized_keys: :error
          )
  def schema, do: @schema

  # Reserve real state bytes while work is pending. A failed completion can
  # release them for a small terminal record, even when other state is full.
  def completion_reserve, do: String.duplicate(" ", 512)

  def records_schema,
    do:
      Zoi.map(Zoi.string() |> Zoi.min(1), @schema)
      |> Zoi.refine({__MODULE__, :portable_records, []})
      |> Zoi.default(%{})

  def portable_records(records, _) do
    with true <- Enum.all?(records, fn {id, record} -> id == record.id end),
         :ok <- Jido.Action.validate_static_data(records) do
      :ok
    else
      _ -> {:error, "Request records must have matching IDs and portable values"}
    end
  end
end
