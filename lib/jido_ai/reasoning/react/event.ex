defmodule Jido.AI.Reasoning.ReAct.Event do
  @moduledoc """
  Compatibility wrapper around `Jido.AI.Runtime.Event`.

  ReAct still emits `:input_injected` as a runtime-only compatibility event even
  though that kind is not part of the generic shared runtime event contract.
  """

  alias Jido.AI.Runtime.Event, as: RuntimeEvent

  @kind_values RuntimeEvent.kinds() ++ [:input_injected]

  @type t :: %__MODULE__{
          id: String.t(),
          seq: integer(),
          at_ms: integer(),
          run_id: String.t(),
          request_id: String.t(),
          iteration: integer(),
          kind: atom(),
          llm_call_id: String.t() | nil,
          tool_call_id: String.t() | nil,
          tool_name: String.t() | nil,
          data: map()
        }

  defstruct [
    :id,
    :seq,
    :at_ms,
    :run_id,
    :request_id,
    :iteration,
    :kind,
    :llm_call_id,
    :tool_call_id,
    :tool_name,
    data: %{}
  ]

  @doc false
  def schema, do: RuntimeEvent.schema()

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

    case Zoi.parse(RuntimeEvent.schema(), attrs) do
      {:ok, event} ->
        event
        |> validate_kind!()
        |> Map.from_struct()
        |> then(&struct!(__MODULE__, &1))

      {:error, errors} ->
        raise ArgumentError, "invalid ReAct event: #{inspect(errors)}"
    end
  end

  defp validate_kind!(%RuntimeEvent{kind: kind} = event) when kind in @kind_values, do: event

  defp validate_kind!(%RuntimeEvent{kind: kind}) do
    raise ArgumentError,
          "invalid ReAct event kind: #{inspect(kind)}; expected one of #{inspect(@kind_values)}"
  end
end
