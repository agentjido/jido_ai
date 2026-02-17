defmodule Jido.AI.ReAct.Event do
  @moduledoc """
  Canonical event envelope emitted by the ReAct runtime.
  """

  @kind_values [
    :request_started,
    :llm_started,
    :llm_delta,
    :llm_completed,
    :tool_started,
    :tool_completed,
    :checkpoint,
    :request_completed,
    :request_failed,
    :request_cancelled
  ]

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              seq: Zoi.integer(),
              at_ms: Zoi.integer(),
              run_id: Zoi.string(),
              request_id: Zoi.string(),
              iteration: Zoi.integer(),
              kind: Zoi.atom(),
              llm_call_id: Zoi.string() |> Zoi.nullish(),
              tool_call_id: Zoi.string() |> Zoi.nullish(),
              tool_name: Zoi.string() |> Zoi.nullish(),
              data: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @spec kinds() :: [atom()]
  def kinds, do: @kind_values

  @doc """
  Create a new event envelope.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.put_new(:id, "evt_#{Jido.Util.generate_id()}")
      |> Map.put_new(:at_ms, System.system_time(:millisecond))
      |> Map.put_new(:llm_call_id, nil)
      |> Map.put_new(:tool_call_id, nil)
      |> Map.put_new(:tool_name, nil)
      |> Map.put_new(:data, %{})

    case Zoi.parse(@schema, attrs) do
      {:ok, event} -> validate_kind!(event)
      {:error, errors} -> raise ArgumentError, "invalid ReAct event: #{inspect(errors)}"
    end
  end

  defp validate_kind!(%__MODULE__{kind: kind} = event) when kind in @kind_values, do: event

  defp validate_kind!(%__MODULE__{kind: kind}) do
    raise ArgumentError,
          "invalid ReAct event kind: #{inspect(kind)}; expected one of #{inspect(@kind_values)}"
  end
end
