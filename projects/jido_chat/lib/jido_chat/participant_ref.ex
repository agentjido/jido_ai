defmodule Jido.Chat.ParticipantRef do
  use TypedStruct

  typedstruct do
    field(:participant_id, String.t(), enforce: true)
    field(:display_name, String.t(), enforce: true)
    field(:ref_type, :mention, default: :mention)
    field(:offset, non_neg_integer(), enforce: true)
    field(:length, pos_integer(), enforce: true)
  end

  def new(participant_id, display_name, offset, length)
      when is_binary(participant_id) and
             is_binary(display_name) and
             is_integer(offset) and offset >= 0 and
             is_integer(length) and length > 0 do
    %__MODULE__{
      participant_id: participant_id,
      display_name: display_name,
      ref_type: :mention,
      offset: offset,
      length: length
    }
  end

  def new(attrs) do
    {:ok,
     %__MODULE__{
       participant_id: attrs.participant_id,
       display_name: attrs.display_name,
       ref_type: :mention,
       offset: attrs.offset,
       length: attrs.length
     }}
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, participant_ref} -> participant_ref
    end
  end
end
