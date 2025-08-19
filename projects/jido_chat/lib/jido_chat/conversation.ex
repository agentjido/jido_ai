# defmodule JidoChat.Conversation do
#   @moduledoc """
#   Represents a conversation context suitable for LLM processing.

#   This module provides functionality to format and manage conversations between humans and AI agents,
#   supporting multiple LLM-specific formats like ChatML and Anthropic.

#   ## Features

#   - Formats messages for different LLM providers
#   - Manages conversation context and metadata
#   - Supports role-based message formatting
#   - Configurable message limits and metadata inclusion
#   - Multiple output format options

#   ## Usage

#       # Create a conversation from messages
#       {:ok, conversation} = Conversation.from_messages(messages, participants,
#         message_limit: 10,
#         format: :chat_ml,
#         include_metadata: false
#       )

#       # Convert to specific format
#       {:ok, formatted} = Conversation.to_format(conversation, :anthropic)

#   ## Message Formats

#   Supports the following formats:
#   - `:chat_ml` - OpenAI ChatML format
#   - `:anthropic` - Anthropic's conversation format
#   - `:raw` - Unformatted message list
#   """

#   alias JidoChat.Participant

#   @type t :: %__MODULE__{
#           messages: [formatted_message()],
#           participants: [Participant.t()],
#           metadata: map()
#         }

#   @type formatted_message :: %{
#           role: String.t(),
#           content: String.t(),
#           name: String.t() | nil,
#           metadata: map()
#         }

#   defstruct [:messages, :participants, metadata: %{}]

#   @doc """
#   Creates a conversation context from channel messages and participants.

#   Takes a list of messages and participants and formats them into a structured conversation
#   suitable for LLM processing. Supports configurable message limits and formatting options.

#   ## Parameters

#     * `messages` - List of chat messages to include
#     * `participants` - List of conversation participants
#     * `opts` - Keyword list of options

#   ## Options

#     * `:message_limit` - Maximum number of messages to include (default: 10)
#     * `:include_metadata` - Whether to include message metadata (default: false)
#     * `:format` - Output format (:chat_ml | :anthropic | :raw) (default: :chat_ml)

#   ## Returns

#     * `{:ok, conversation}` - Successfully created conversation struct
#     * `{:error, reason}` - If conversation creation fails

#   ## Examples

#       iex> messages = [%Message{content: "Hello", participant_id: "user1"}]
#       iex> participants = [%Participant{id: "user1", type: :human}]
#       iex> {:ok, conv} = Conversation.from_messages(messages, participants)
#       iex> length(conv.messages)
#       1
#   """
#   def from_messages(messages, participants, opts \\ []) do
#     limit = Keyword.get(opts, :message_limit, 10)
#     format = Keyword.get(opts, :format, :chat_ml)
#     include_metadata = Keyword.get(opts, :include_metadata, false)

#     formatted_messages =
#       messages
#       |> Enum.take(limit)
#       |> Enum.map(&format_message(&1, participants, include_metadata))

#     conversation = %__MODULE__{
#       messages: formatted_messages,
#       participants: participants,
#       metadata: %{
#         format: format,
#         created_at: DateTime.utc_now(),
#         message_count: length(formatted_messages)
#       }
#     }

#     {:ok, conversation}
#   end

#   # Formats a single message with participant information and optional metadata.
#   #
#   # Parameters:
#   #   * message - The message to format
#   #   * participants - List of conversation participants
#   #   * include_metadata - Whether to include message metadata
#   #
#   # Returns a formatted message map with role, content and optional fields.
#   defp format_message(message, participants, include_metadata) do
#     participant = Enum.find(participants, &(&1.id == message.participant_id))

#     base_message = %{
#       role: get_role(participant),
#       content: message.content,
#       name: participant && participant.name
#     }

#     if include_metadata do
#       Map.put(base_message, :metadata, message.metadata)
#     else
#       base_message
#     end
#   end

#   # Determines the role for a participant based on their type.
#   #
#   # Parameters:
#   #   * participant - The participant struct or nil
#   #
#   # Returns "user", "assistant", or "system" based on participant type.
#   defp get_role(%{type: :human}), do: "user"
#   defp get_role(%{type: :agent}), do: "assistant"
#   defp get_role(_), do: "system"

#   @doc """
#   Converts the conversation to various LLM-specific formats.

#   Transforms the conversation into a format suitable for different LLM providers.

#   ## Parameters

#     * `conversation` - The conversation struct to format
#     * `format` - Desired output format (:chat_ml | :anthropic | :raw)

#   ## Returns

#     * `{:ok, formatted}` - Successfully formatted conversation
#     * `{:error, :unsupported_format}` - If format is not supported

#   ## Examples

#       iex> {:ok, formatted} = Conversation.to_format(conversation, :chat_ml)
#       iex> is_list(formatted)
#       true
#   """
#   def to_format(%__MODULE__{} = conversation, format) do
#     case format do
#       :chat_ml -> to_chat_ml(conversation)
#       :anthropic -> to_anthropic(conversation)
#       :raw -> {:ok, conversation.messages}
#       _ -> {:error, :unsupported_format}
#     end
#   end

#   # Formats conversation for ChatML (OpenAI) format.
#   #
#   # Parameters:
#   #   * conversation - The conversation to format
#   #
#   # Returns {:ok, messages} where messages is a list of ChatML-formatted messages.
#   defp to_chat_ml(conversation) do
#     messages =
#       Enum.map(conversation.messages, fn msg ->
#         %{
#           role: msg.role,
#           content: msg.content,
#           name: msg.name
#         }
#       end)

#     {:ok, messages}
#   end

#   # Formats conversation for Anthropic's conversation format.
#   #
#   # Parameters:
#   #   * conversation - The conversation to format
#   #
#   # Returns {:ok, string} containing the Anthropic-formatted conversation.
#   defp to_anthropic(conversation) do
#     {:ok, "Human: " <> format_anthropic_messages(conversation.messages)}
#   end

#   # Formats messages into Anthropic's specific conversation format.
#   #
#   # Parameters:
#   #   * messages - List of messages to format
#   #
#   # Returns a string with messages formatted as "Human: " and "Assistant: " prefixes.
#   defp format_anthropic_messages(messages) do
#     messages
#     |> Enum.map_join("\n\n", fn
#       %{role: "user"} = msg -> "Human: #{msg.content}"
#       %{role: "assistant"} = msg -> "Assistant: #{msg.content}"
#       %{role: "system"} = msg -> msg.content
#     end)
#   end
# end
