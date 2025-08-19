defmodule Jido.Dialogue.Conversation do
  @moduledoc """
  Represents a conversation with its turns and metadata.
  """

  alias Jido.Dialogue.{Types, Turn}

  @enforce_keys [:id]
  defstruct [
    :id,
    state: :initial,
    turns: [],
    context: %{},
    metadata: %{},
    start_time: nil,
    end_time: nil
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          state: Types.state(),
          turns: [Turn.t()],
          context: map(),
          metadata: map(),
          start_time: Types.timestamp() | nil,
          end_time: Types.timestamp() | nil
        }

  @spec new(String.t(), map()) :: t()
  def new(id, metadata \\ %{}) do
    %__MODULE__{
      id: id,
      metadata: metadata,
      start_time: DateTime.utc_now()
    }
  end

  @spec add_turn(t(), Turn.t()) :: t()
  def add_turn(%__MODULE__{} = conversation, %Turn{} = turn) do
    %{conversation | turns: conversation.turns ++ [turn], state: :active}
  end

  @spec update_context(t(), map()) :: t()
  def update_context(%__MODULE__{} = conversation, new_context) do
    %{conversation | context: Map.merge(conversation.context, new_context)}
  end

  @spec complete(t()) :: t()
  def complete(%__MODULE__{} = conversation) do
    %{conversation | state: :completed, end_time: DateTime.utc_now()}
  end

  @spec latest_turn(t()) :: Turn.t() | nil
  def latest_turn(%__MODULE__{turns: []}), do: nil
  def latest_turn(%__MODULE__{turns: turns}), do: List.last(turns)

  @spec turn_count(t()) :: non_neg_integer()
  def turn_count(%__MODULE__{turns: turns}), do: length(turns)

  @spec duration(t()) :: integer() | nil
  def duration(%__MODULE__{start_time: nil}), do: nil
  def duration(%__MODULE__{end_time: nil}), do: nil

  def duration(%__MODULE__{start_time: start_time, end_time: end_time}) do
    DateTime.diff(end_time, start_time, :second)
  end
end
