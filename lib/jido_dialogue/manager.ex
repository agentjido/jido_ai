defmodule Jido.Dialogue.Manager do
  @moduledoc """
  Manages conversations and their state.
  """

  alias Jido.Dialogue.{Conversation, Turn, Types}

  @spec start_conversation(String.t(), map()) :: Conversation.t()
  def start_conversation(id, metadata \\ %{}) do
    Conversation.new(id, metadata)
  end

  @spec add_message(Conversation.t(), Types.speaker(), String.t(), map()) :: Conversation.t()
  def add_message(conversation, speaker, content, metadata \\ %{}) do
    turn = Turn.new(speaker, content, metadata)
    Conversation.add_turn(conversation, turn)
  end

  @spec get_history(Conversation.t()) :: [Turn.t()]
  def get_history(%Conversation{turns: turns}), do: turns

  @spec get_context(Conversation.t()) :: map()
  def get_context(%Conversation{context: context}), do: context
end
