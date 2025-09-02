defmodule Jido.AI.Messages do
  @moduledoc """
  Convenient helper functions for creating AI messages following Vercel AI SDK patterns.

  This module provides simple builder functions for common message types, making it easy
  to construct conversations with AI models without needing to manually build Message structs.

  ## Basic Message Builders

      iex> import Jido.AI.Messages
      iex> user("Hello, how are you?")
      %Jido.AI.Message{role: :user, content: "Hello, how are you?"}

      iex> system("You are a helpful assistant")
      %Jido.AI.Message{role: :system, content: "You are a helpful assistant"}

      iex> assistant("I'm doing well, thank you!")
      %Jido.AI.Message{role: :assistant, content: "I'm doing well, thank you!"}

  ## Multi-Modal Content

      # Text with image URL
      user_with_image("Describe this image", "https://example.com/photo.jpg")

      # Text with file data
      pdf_data = File.read!("report.pdf")
      user_with_file("Summarize this PDF", pdf_data, "application/pdf", "report.pdf")

  ## Tool Integration

      # Tool result from function call
      tool_result("call_abc123", "get_weather", %{temperature: 72, humidity: 65})

  ## Conversation Flows

      messages = [
        system("You are a weather assistant"),
        user("What's the weather like?"),
        assistant("I'll check the weather for you", [
          tool_call("call_123", "get_weather", %{location: "San Francisco"})
        ]),
        tool_result("call_123", "get_weather", %{temp: 68, condition: "sunny"}),
        assistant("It's 68°F and sunny in San Francisco!")
      ]

  All functions return valid `Jido.AI.Message` structs that can be used with any
  AI provider through the main `Jido.AI.generate_text/3` API.
  """

  alias Jido.AI.Error
  alias Jido.AI.{ContentPart, Message}

  @doc """
  Creates a user message with the given content.

  ## Examples

      iex> user("Hello world")
      %Jido.AI.Message{role: :user, content: "Hello world"}

      iex> user("Hello", %{priority: "high"})
      %Jido.AI.Message{role: :user, content: "Hello", metadata: %{priority: "high"}}
  """
  @spec user(String.t()) :: Message.t()
  @spec user(String.t(), map()) :: Message.t()
  def user(content, metadata \\ %{}) do
    %Message{role: :user, content: content, metadata: metadata}
  end

  @doc """
  Creates an assistant message with the given content.

  ## Examples

      iex> assistant("How can I help you?")
      %Jido.AI.Message{role: :assistant, content: "How can I help you?"}

      iex> assistant("Here's the result", %{confidence: 0.95})
      %Jido.AI.Message{role: :assistant, content: "Here's the result", metadata: %{confidence: 0.95}}
  """
  @spec assistant(String.t()) :: Message.t()
  @spec assistant(String.t(), map()) :: Message.t()
  def assistant(content, metadata \\ %{}) do
    %Message{role: :assistant, content: content, metadata: metadata}
  end

  @doc """
  Creates a system message with the given content.

  System messages provide instructions or context to the AI model about its role and behavior.

  ## Examples

      iex> system("You are a helpful coding assistant")
      %Jido.AI.Message{role: :system, content: "You are a helpful coding assistant"}

      iex> system("Respond in French only", %{language: "fr"})
      %Jido.AI.Message{role: :system, content: "Respond in French only", metadata: %{language: "fr"}}
  """
  @spec system(String.t()) :: Message.t()
  @spec system(String.t(), map()) :: Message.t()
  def system(content, metadata \\ %{}) do
    %Message{role: :system, content: content, metadata: metadata}
  end

  @doc """
  Creates a tool result message linking output to a previous tool call.

  ## Examples

      iex> tool_result("call_123", "get_weather", %{temp: 72})
      %Jido.AI.Message{
        role: :tool,
        content: [%Jido.AI.ContentPart{type: :tool_result, tool_call_id: "call_123", tool_name: "get_weather", output: %{temp: 72}}],
        tool_call_id: "call_123"
      }

      iex> tool_result("call_456", "search", ["result1", "result2"], %{count: 2})
      %Jido.AI.Message{
        role: :tool,
        content: [%Jido.AI.ContentPart{type: :tool_result, tool_call_id: "call_456", tool_name: "search", output: ["result1", "result2"]}],
        tool_call_id: "call_456",
        metadata: %{count: 2}
      }
  """
  @spec tool_result(String.t(), String.t(), any()) :: Message.t()
  @spec tool_result(String.t(), String.t(), any(), map()) :: Message.t()
  def tool_result(tool_call_id, tool_name, output, metadata \\ %{}) do
    content_part = %ContentPart{
      type: :tool_result,
      tool_call_id: tool_call_id,
      tool_name: tool_name,
      output: output
    }

    %Message{
      role: :tool,
      content: [content_part],
      tool_call_id: tool_call_id,
      metadata: metadata
    }
  end

  @doc """
  Creates a user message with text and an image URL.

  ## Examples

      iex> user_with_image("Describe this", "https://example.com/image.png")
      %Jido.AI.Message{
        role: :user,
        content: [
          %Jido.AI.ContentPart{type: :text, text: "Describe this"},
          %Jido.AI.ContentPart{type: :image_url, url: "https://example.com/image.png"}
        ]
      }

      iex> user_with_image("What's in this photo?", "https://example.com/photo.jpg", %{detail: "high"})
      %Jido.AI.Message{
        role: :user,
        content: [
          %Jido.AI.ContentPart{type: :text, text: "What's in this photo?"},
          %Jido.AI.ContentPart{type: :image_url, url: "https://example.com/photo.jpg"}
        ],
        metadata: %{detail: "high"}
      }
  """
  @spec user_with_image(String.t(), String.t()) :: Message.t()
  @spec user_with_image(String.t(), String.t(), map()) :: Message.t()
  def user_with_image(text, image_url, metadata \\ %{}) do
    content = [
      %ContentPart{type: :text, text: text},
      %ContentPart{type: :image_url, url: image_url}
    ]

    %Message{role: :user, content: content, metadata: metadata}
  end

  @doc """
  Creates a user message with text and file data.

  ## Examples

      iex> pdf_data = <<"%PDF-1.4...">>
      iex> user_with_file("Analyze this", pdf_data, "application/pdf", "report.pdf")
      %Jido.AI.Message{
        role: :user,
        content: [
          %Jido.AI.ContentPart{type: :text, text: "Analyze this"},
          %Jido.AI.ContentPart{type: :file, data: <<"%PDF-1.4...">>, media_type: "application/pdf", filename: "report.pdf"}
        ]
      }

      iex> json_data = "{\"key\": \"value\"}"
      iex> user_with_file("Process this JSON", json_data, "application/json", "data.json", %{encoding: "utf8"})
      %Jido.AI.Message{
        role: :user,
        content: [
          %Jido.AI.ContentPart{type: :text, text: "Process this JSON"},
          %Jido.AI.ContentPart{type: :file, data: "{\"key\": \"value\"}", media_type: "application/json", filename: "data.json"}
        ],
        metadata: %{encoding: "utf8"}
      }
  """
  @spec user_with_file(String.t(), binary(), String.t(), String.t()) :: Message.t()
  @spec user_with_file(String.t(), binary(), String.t(), String.t(), map()) :: Message.t()
  def user_with_file(text, file_data, media_type, filename, metadata \\ %{}) do
    content = [
      %ContentPart{type: :text, text: text},
      %ContentPart{type: :file, data: file_data, media_type: media_type, filename: filename}
    ]

    %Message{role: :user, content: content, metadata: metadata}
  end

  @doc """
  Validates messages for use with AI text generation.

  Accepts either:
  - A non-empty string (simple text prompt) 
  - A list of valid Message structs (conversation)

  Returns `{:ok, messages}` if valid, or `{:error, validation_error}` if invalid.

  ## Examples

      # Valid string prompt
      iex> validate("Tell me a joke")
      {:ok, "Tell me a joke"}

      # Valid message array  
      iex> messages = [user("Hello"), assistant("Hi there")]
      iex> validate(messages)
      {:ok, [%Jido.AI.Message{role: :user, content: "Hello"}, %Jido.AI.Message{role: :assistant, content: "Hi there"}]}

      # Invalid empty string
      iex> validate("")
      {:error, %Jido.AI.Error.Validation.Error{tag: :empty_prompt}}

  """
  @spec validate(String.t() | [Message.t()]) :: {:ok, String.t() | [Message.t()]} | {:error, Error.t()}
  def validate(prompt) when is_binary(prompt) and prompt != "" do
    {:ok, prompt}
  end

  def validate(messages) when is_list(messages) do
    case validate_messages(messages) do
      :ok -> {:ok, messages}
      {:error, reason} -> {:error, Error.validation_error(:invalid_messages, reason)}
    end
  end

  def validate("") do
    {:error, Error.validation_error(:empty_prompt, "Messages cannot be empty")}
  end

  def validate(_) do
    {:error, Error.validation_error(:invalid_messages, "Expected string or message list")}
  end

  @doc """
  Validates that a list contains only valid Message structs.

  Returns `:ok` if all messages are valid, or `{:error, reason}` with details about validation failures.

  ## Examples

      iex> messages = [user("Hello"), assistant("Hi there")]
      iex> validate_messages(messages)
      :ok

      iex> validate_messages([%{invalid: "message"}])
      {:error, "Message at index 0 is not a valid Message struct"}

      iex> validate_messages("not a list")
      {:error, "Expected a list of messages, got: \"not a list\""}
  """
  @spec validate_messages([Message.t()]) :: :ok | {:error, String.t()}
  def validate_messages(messages) when is_list(messages) do
    if Enum.empty?(messages) do
      {:error, "Message list cannot be empty"}
    else
      messages
      |> Enum.with_index()
      |> Enum.reduce_while(:ok, fn {message, index}, _acc ->
        case validate_message(message) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, "Message at index #{index}: #{reason}"}}
        end
      end)
    end
  end

  def validate_messages(messages) do
    {:error, "Expected a list of messages, got: #{inspect(messages)}"}
  end

  @doc """
  Validates that a single message is a valid Message struct.

  ## Examples

      iex> validate_message(user("Hello"))
      :ok

      iex> validate_message(%{role: :user, content: "Hello"})
      {:error, "Not a valid Message struct"}

      iex> validate_message(nil)
      {:error, "Message cannot be nil"}
  """
  @spec validate_message(Message.t() | any()) :: :ok | {:error, String.t()}
  def validate_message(%Message{role: role, content: content} = _message) do
    with :ok <- validate_role(role) do
      validate_content(content)
    end
  end

  def validate_message(nil), do: {:error, "Message cannot be nil"}
  def validate_message(_), do: {:error, "Not a valid Message struct"}

  # Private validation helpers

  defp validate_role(role) when role in [:user, :assistant, :system, :tool], do: :ok
  defp validate_role(role), do: {:error, "Invalid role: #{inspect(role)}. Must be :user, :assistant, :system, or :tool"}

  defp validate_content(content) when is_binary(content), do: :ok

  defp validate_content(content) when is_list(content) do
    if Enum.all?(content, &valid_content_part?/1) do
      :ok
    else
      {:error, "Content list contains invalid ContentPart structs"}
    end
  end

  defp validate_content(content),
    do: {:error, "Content must be a string or list of ContentPart structs, got: #{inspect(content)}"}

  defp valid_content_part?(%ContentPart{type: type})
       when type in [:text, :image_url, :image, :file, :tool_call, :tool_result],
       do: true

  defp valid_content_part?(_), do: false
end
