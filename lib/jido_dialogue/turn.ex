defmodule Jido.Dialogue.Turn do
  @moduledoc """
  Represents a single turn in a conversation.
  """

  alias Jido.Dialogue.Types

  @enforce_keys [:id, :speaker, :content, :timestamp]
  defstruct [
    :id,
    :speaker,
    :content,
    :timestamp,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          id: Types.turn_id(),
          speaker: Types.speaker(),
          content: String.t(),
          timestamp: Types.timestamp(),
          metadata: map()
        }

  @spec new(Types.speaker(), String.t(), map()) :: t()
  def new(speaker, content, metadata \\ %{}) do
    %__MODULE__{
      id: generate_id(),
      speaker: speaker,
      content: content,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }
  end

  defp generate_id, do: UUID.uuid4()
end
