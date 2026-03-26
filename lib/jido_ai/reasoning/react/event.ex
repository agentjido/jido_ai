defmodule Jido.AI.Reasoning.ReAct.Event do
  @moduledoc """
  Compatibility wrapper around `Jido.AI.Runtime.Event`.
  """

  alias Jido.AI.Runtime.Event, as: RuntimeEvent

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
  def kinds, do: RuntimeEvent.kinds()

  @doc """
  Create a new event envelope.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs
    |> RuntimeEvent.new()
    |> Map.from_struct()
    |> then(&struct!(__MODULE__, &1))
  end
end
