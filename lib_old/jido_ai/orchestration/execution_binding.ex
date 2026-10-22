defmodule Jido.AI.Orchestration.ExecutionBinding do
  @moduledoc false

  # Live access for one admitted request. This value is never Agent state or
  # checkpoint data. Only the Coordinator constructs it for managed execution.
  @schema Zoi.struct(
            __MODULE__,
            %{
              coordinator: Zoi.pid(),
              agent_server: Zoi.pid(),
              request_id: Zoi.string() |> Zoi.min(1),
              run_id: Zoi.string() |> Zoi.min(1),
              source: Zoi.string(),
              extra_refs: Zoi.map() |> Zoi.default(%{}),
              retain_history?: Zoi.boolean(),
              input_queue: Zoi.pid() |> Zoi.nullable() |> Zoi.default(nil),
              checkpoint: Zoi.map() |> Zoi.nullable() |> Zoi.default(nil)
            },
            coerce: true
          )
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def new(attributes) do
    case Zoi.parse(@schema, attributes) do
      {:ok, binding} -> {:ok, binding}
      {:error, _} -> {:error, :invalid_execution_binding}
    end
  end

  def fetch(context) do
    case Map.fetch(context, :jido_ai_execution) do
      {:ok, %__MODULE__{} = binding} ->
        new(binding)

      {:ok, _} ->
        {:error, :invalid_execution_binding}

      :error ->
        if context[:jido_ai_admission_profile],
          do: {:error, :missing_execution_binding},
          else: {:ok, nil}
    end
  end
end
