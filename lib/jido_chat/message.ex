defmodule Jido.Chat.Message do
  @moduledoc """
  Defines the structure of a chat message.

  This is a lightweight struct that represents a chat message in the system.
  It's designed to be easily convertible to and from a Jido.Signal.
  """
  use TypedStruct

  alias Jido.Chat.Message.Parser

  typedstruct enforce: [:type, :room_id, :sender, :content, :timestamp] do
    field(:id, String.t())
    field(:type, String.t())
    field(:room_id, String.t())
    field(:sender, String.t())
    field(:content, String.t())
    field(:timestamp, DateTime.t())
    field(:metadata, map(), default: %{})
  end

  @doc """
  Represents the data field in a chat signal.
  """
  typedstruct module: ChatData, enforce: [:room_id, :sender, :content] do
    field(:room_id, String.t())
    field(:sender, String.t())
    field(:content, String.t())
    field(:metadata, map(), default: %{})
  end

  # Define a hierarchical type system for chat messages
  @config %{
    separator: ".",
    chat_prefix: "chat"
  }

  # Base type paths
  @message_base [@config.chat_prefix, "message"]
  @system_base [@config.chat_prefix, "system"]
  @room_base [@config.chat_prefix, "room"]

  # Message type helpers
  def type(:message), do: join_type(@message_base)
  def type(:join), do: join_type(@room_base ++ ["join"])
  def type(:leave), do: join_type(@room_base ++ ["leave"])
  def type(:room_created), do: join_type(@room_base ++ ["created"])
  def type(:room_deleted), do: join_type(@room_base ++ ["deleted"])
  def type(:system_notification), do: join_type(@system_base ++ ["notification"])
  def type(:system_error), do: join_type(@system_base ++ ["error"])
  def type(:turn_notification), do: join_type(@room_base ++ ["turn"])

  @doc """
  Creates a new message with the given attributes.

  Automatically generates an ID if one is not provided.

  Returns `{:ok, message}`.

  Note: This function only creates the message struct. If you need to parse mentions
  in a chat message, you should call `parse_message/1` after creating the message.
  """
  @spec new(map()) :: {:ok, t()}
  def new(attrs) do
    # Generate a unique ID for the message
    id = "msg_#{:erlang.unique_integer([:positive])}"

    # Create the message struct
    message = %__MODULE__{
      id: id,
      type: attrs.type,
      room_id: attrs.room_id,
      sender: attrs.sender,
      content: attrs.content,
      timestamp: attrs.timestamp,
      metadata: attrs[:metadata] || %{}
    }

    {:ok, message}
  end

  @doc """
  Parses a message for @mentions and updates the metadata.

  This function should be called after creating a message with `new/1` if you need
  to detect and process mentions in the message content.

  ## Parameters

  - `message` - The message to parse

  ## Returns

  - The updated message with participant references in metadata

  ## Examples

      iex> {:ok, message} = Message.new(%{type: "chat.message", room_id: "room1", sender: "user1", content: "Hello @alice!", timestamp: DateTime.utc_now()})
      iex> message = Message.parse_message(message)
      iex> message.metadata.participant_refs
      ["alice"]
  """
  @spec parse_message(t()) :: t()
  def parse_message(message) do
    # Parse the message content for @mentions
    case Parser.parse(message.content) do
      {:ok, _parsed_content, []} ->
        # No mentions found
        message

      {:ok, _parsed_content, participant_refs} ->
        # Add the participant references to the metadata
        metadata = Map.put(message.metadata, :participant_refs, participant_refs)
        %{message | metadata: metadata}

      {:error, _reason} ->
        # Error parsing the message, return it unchanged
        message
    end
  end

  @doc """
  Creates a message from a signal.

  Extracts the message data from a signal and creates a Message struct.

  Returns a Message struct.
  """
  @spec from_signal(Jido.Signal.t()) :: t()
  def from_signal(signal) do
    message = %__MODULE__{
      id: signal.id,
      type: signal.type,
      room_id: signal.data.room_id,
      sender: signal.data.sender,
      content: signal.data.content,
      timestamp: signal.time || DateTime.utc_now(),
      metadata: signal.data.metadata || %{}
    }

    {:ok, message}
  end

  @doc """
  Converts a message to a signal.

  Creates a Jido.Signal struct from the message data.

  Returns a Jido.Signal struct.
  """
  @spec to_signal(t()) :: Jido.Signal.t()
  def to_signal(message) do
    %Jido.Signal{
      id: message.id,
      type: message.type,
      source: "jido_chat",
      subject: "jido://chat/room/#{message.room_id}",
      data: %ChatData{
        room_id: message.room_id,
        sender: message.sender,
        content: message.content,
        metadata: message.metadata
      }
    }
  end

  @doc """
  Creates a standard chat message signal.

  ## Parameters
  - room_id: The ID of the room
  - sender: The username of the sender
  - content: The message content
  - opts: Additional options

  ## Returns
  A Jido.Signal struct
  """
  @spec chat_message(String.t(), String.t(), String.t(), map()) :: Jido.Signal.t()
  def chat_message(room_id, sender, content, opts \\ %{}) do
    create_signal(
      type: :message,
      room_id: room_id,
      sender: sender,
      content: content,
      opts: opts
    )
  end

  @doc """
  Creates a room join signal.

  ## Parameters
  - room_id: The ID of the room
  - username: The username of the user joining
  - opts: Additional options

  ## Returns
  A Jido.Signal struct
  """
  @spec join_room(String.t(), String.t(), map()) :: Jido.Signal.t()
  def join_room(room_id, username, opts \\ %{}) do
    create_signal(
      type: :join,
      room_id: room_id,
      sender: username,
      content: "#{username} has joined the room",
      opts: opts
    )
  end

  @doc """
  Creates a room leave signal.

  ## Parameters
  - room_id: The ID of the room
  - username: The username of the user leaving
  - opts: Additional options

  ## Returns
  A Jido.Signal struct
  """
  @spec leave_room(String.t(), String.t(), map()) :: Jido.Signal.t()
  def leave_room(room_id, username, opts \\ %{}) do
    create_signal(
      type: :leave,
      room_id: room_id,
      sender: username,
      content: "#{username} has left the room",
      opts: opts
    )
  end

  @doc """
  Creates a room created signal.

  ## Parameters
  - room_id: The ID of the room
  - room_name: The name of the room
  - opts: Additional options

  ## Returns
  A Jido.Signal struct
  """
  @spec room_created(String.t(), String.t(), map()) :: Jido.Signal.t()
  def room_created(room_id, room_name, opts \\ %{}) do
    create_signal(
      type: :room_created,
      room_id: room_id,
      sender: "system",
      content: "Room created: #{room_name}",
      opts: opts
    )
  end

  @doc """
  Creates a system notification signal.

  ## Parameters
  - room_id: The ID of the room
  - content: The notification content
  - opts: Additional options

  ## Returns
  A Jido.Signal struct
  """
  @spec system_notification(String.t(), String.t(), map()) :: Jido.Signal.t()
  def system_notification(room_id, content, opts \\ %{}) do
    create_signal(
      type: :system_notification,
      room_id: room_id,
      sender: "system",
      content: content,
      opts: opts
    )
  end

  @doc """
  Creates a turn notification signal.

  ## Parameters
  - room_id: The ID of the room
  - participant_id: The ID of the participant whose turn it is
  - opts: Additional options

  ## Returns
  A Jido.Signal struct
  """
  @spec turn_notification(String.t(), String.t(), map()) :: Jido.Signal.t()
  def turn_notification(room_id, participant_id, opts \\ %{}) do
    create_signal(
      type: :turn_notification,
      room_id: room_id,
      sender: "system",
      content: "It's #{participant_id}'s turn to speak",
      metadata: %{participant_id: participant_id},
      opts: opts
    )
  end

  # Helper functions

  @doc """
  Creates a signal with the given parameters.

  ## Parameters
  - params: A keyword list with the following keys:
    - type: The message type (atom)
    - room_id: The ID of the room
    - sender: The username of the sender
    - content: The message content
    - opts: Additional options (optional)
    - metadata: Additional metadata (optional)

  ## Returns
  A Jido.Signal struct
  """
  @spec create_signal(keyword()) :: Jido.Signal.t()
  def create_signal(params) do
    message_type = Keyword.fetch!(params, :type)
    room_id = Keyword.fetch!(params, :room_id)
    sender = Keyword.fetch!(params, :sender)
    content = Keyword.fetch!(params, :content)
    opts = Keyword.get(params, :opts, %{})
    metadata = Keyword.get(params, :metadata, %{})

    Jido.Signal.new!(%{
      type: type(message_type),
      source: "jido_chat",
      subject: "jido://chat/room/#{room_id}",
      data: %ChatData{
        room_id: room_id,
        sender: sender,
        content: content,
        metadata: metadata
      },
      jido_opts: opts
    })
  end

  defp join_type(type) when is_list(type) do
    Enum.join(type, @config.separator)
  end
end

defimpl Jido.AI.Promptable, for: Jido.Chat.Message do
  @doc """
  Converts a chat message to a prompt string suitable for an LLM.

  The format depends on the message type:
  - Regular messages: "[sender]: [content]"
  - System messages: "[SYSTEM]: [content]"
  - Join/leave messages: "[ROOM EVENT]: [content]"
  - Turn notifications: "[TURN]: [content]"

  If the message contains mentions, they are preserved in the content.
  """
  def to_prompt(message) do
    prefix = get_prefix(message.type)
    "#{prefix}#{message.sender}: #{message.content}"
  end

  # Helper to determine the appropriate prefix based on message type
  defp get_prefix(type) do
    cond do
      type == Jido.Chat.Message.type(:message) -> ""
      type == Jido.Chat.Message.type(:system_notification) -> "[SYSTEM] "
      type == Jido.Chat.Message.type(:system_error) -> "[SYSTEM ERROR] "
      type == Jido.Chat.Message.type(:join) -> "[ROOM EVENT] "
      type == Jido.Chat.Message.type(:leave) -> "[ROOM EVENT] "
      type == Jido.Chat.Message.type(:room_created) -> "[ROOM EVENT] "
      type == Jido.Chat.Message.type(:room_deleted) -> "[ROOM EVENT] "
      type == Jido.Chat.Message.type(:turn_notification) -> "[TURN] "
      true -> "[UNKNOWN] "
    end
  end
end
