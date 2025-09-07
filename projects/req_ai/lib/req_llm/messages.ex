defmodule ReqLLM.Messages do
  @moduledoc """
  Convenient helper functions for creating AI messages following Vercel AI SDK patterns.

  This module provides simple builder functions for common message types, making it easy
  to construct conversations with AI models without needing to manually build Message structs.

  ## Basic Message Builders

      iex> import ReqLLM.Messages
      iex> user("Hello, how are you?")
      %ReqLLM.Message{role: :user, content: "Hello, how are you?"}

      iex> system("You are a helpful assistant")
      %ReqLLM.Message{role: :system, content: "You are a helpful assistant"}

      iex> assistant("I'm doing well, thank you!")
      %ReqLLM.Message{role: :assistant, content: "I'm doing well, thank you!"}

  ## Multi-Modal Content

      # Text with image URL
      user_with_image("Describe this image", "https://example.com/photo.jpg")

      # Text with file data
      pdf_data = File.read!("report.pdf")
      user_with_file("Summarize this PDF", pdf_data, "application/pdf", "report.pdf")

  ## Tool Integration

      # Tool result from function call
      tool_result("call_abc123", "get_weather", %{temperature: 72, humidity: 65})

  ## Conversation Collections

      messages = ReqLLM.Messages.new([
        system("You are a weather assistant"),
        user("What's the weather like?"),
        assistant("I'll check the weather for you", [
          tool_call("call_123", "get_weather", %{location: "San Francisco"})
        ]),
        tool_result("call_123", "get_weather", %{temp: 68, condition: "sunny"}),
        assistant("It's 68°F and sunny in San Francisco!")
      ])
      
      Enum.count(messages) # => 5
      Enum.map(messages, & &1.role) # => [:system, :user, :assistant, :tool, :assistant]

  All functions return valid `ReqLLM.Message` structs that can be used with any
  AI provider through the main `ReqLLM.generate_text/3` API.
  """

  @enforce_keys [:items]
  defstruct items: []

  @typedoc """
  A wrapper around a list of `%ReqLLM.Message{}` structs that implements Enumerable.

      iex> msgs = [%ReqLLM.Message{role: :user, content: "hi"}]
      ...> coll = ReqLLM.Messages.new(msgs)
      ...> Enum.map(coll, & &1.role)
      [:user]
  """
  @type t :: %__MODULE__{items: [ReqLLM.Message.t()]}

  alias ReqLLM.Error
  alias ReqLLM.{ContentPart, Message}

  # ---------------------------------------------------------------------------
  # Constructors / helpers
  # ---------------------------------------------------------------------------

  @doc "Create a new Messages collection from a list of messages."
  @spec new([ReqLLM.Message.t()]) :: t()
  def new(messages \\ []), do: %__MODULE__{items: messages}

  @doc "Return the underlying list."
  @spec to_list(t()) :: [ReqLLM.Message.t()]
  def to_list(%__MODULE__{items: items}), do: items

  @doc """
  Creates a user message with the given content.

  ## Examples

      iex> user("Hello world")
      %ReqLLM.Message{role: :user, content: "Hello world"}

      iex> user("Hello", %{priority: "high"})
      %ReqLLM.Message{role: :user, content: "Hello", metadata: %{priority: "high"}}
  """
  @spec user(String.t()) :: ReqLLM.Message.t()
  @spec user(String.t(), map()) :: ReqLLM.Message.t()
  def user(content, metadata \\ %{}) do
    %Message{role: :user, content: content, metadata: metadata}
  end

  @doc """
  Creates an assistant message with the given content.

  ## Examples

      iex> assistant("How can I help you?")
      %ReqLLM.Message{role: :assistant, content: "How can I help you?"}

      iex> assistant("Here's the result", %{confidence: 0.95})
      %ReqLLM.Message{role: :assistant, content: "Here's the result", metadata: %{confidence: 0.95}}
  """
  @spec assistant(String.t()) :: ReqLLM.Message.t()
  @spec assistant(String.t(), map()) :: ReqLLM.Message.t()
  def assistant(content, metadata \\ %{}) do
    %Message{role: :assistant, content: content, metadata: metadata}
  end

  @doc """
  Creates a system message with the given content.

  System messages provide instructions or context to the AI model about its role and behavior.

  ## Examples

      iex> system("You are a helpful coding assistant")
      %ReqLLM.Message{role: :system, content: "You are a helpful coding assistant"}

      iex> system("Respond in French only", %{language: "fr"})
      %ReqLLM.Message{role: :system, content: "Respond in French only", metadata: %{language: "fr"}}
  """
  @spec system(String.t()) :: ReqLLM.Message.t()
  @spec system(String.t(), map()) :: ReqLLM.Message.t()
  def system(content, metadata \\ %{}) do
    %Message{role: :system, content: content, metadata: metadata}
  end

  @doc """
  Creates a tool result message linking output to a previous tool call.

  ## Examples

      iex> tool_result("call_123", "get_weather", %{temp: 72})
      %ReqLLM.Message{
        role: :tool,
        content: [%ReqLLM.ContentPart{type: :tool_result, tool_call_id: "call_123", tool_name: "get_weather", output: %{temp: 72}}],
        tool_call_id: "call_123"
      }

      iex> tool_result("call_456", "search", ["result1", "result2"], %{count: 2})
      %ReqLLM.Message{
        role: :tool,
        content: [%ReqLLM.ContentPart{type: :tool_result, tool_call_id: "call_456", tool_name: "search", output: ["result1", "result2"]}],
        tool_call_id: "call_456",
        metadata: %{count: 2}
      }
  """
  @spec tool_result(String.t(), String.t(), any()) :: ReqLLM.Message.t()
  @spec tool_result(String.t(), String.t(), any(), map()) :: ReqLLM.Message.t()
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
      %ReqLLM.Message{
        role: :user,
        content: [
          %ReqLLM.ContentPart{type: :text, text: "Describe this"},
          %ReqLLM.ContentPart{type: :image_url, url: "https://example.com/image.png"}
        ]
      }

      iex> user_with_image("What's in this photo?", "https://example.com/photo.jpg", %{detail: "high"})
      %ReqLLM.Message{
        role: :user,
        content: [
          %ReqLLM.ContentPart{type: :text, text: "What's in this photo?"},
          %ReqLLM.ContentPart{type: :image_url, url: "https://example.com/photo.jpg"}
        ],
        metadata: %{detail: "high"}
      }
  """
  @spec user_with_image(String.t(), String.t()) :: ReqLLM.Message.t()
  @spec user_with_image(String.t(), String.t(), map()) :: ReqLLM.Message.t()
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
      %ReqLLM.Message{
        role: :user,
        content: [
          %ReqLLM.ContentPart{type: :text, text: "Analyze this"},
          %ReqLLM.ContentPart{type: :file, data: <<"%PDF-1.4...">>, media_type: "application/pdf", filename: "report.pdf"}
        ]
      }

      iex> json_data = "{\"key\": \"value\"}"
      iex> user_with_file("Process this JSON", json_data, "application/json", "data.json", %{encoding: "utf8"})
      %ReqLLM.Message{
        role: :user,
        content: [
          %ReqLLM.ContentPart{type: :text, text: "Process this JSON"},
          %ReqLLM.ContentPart{type: :file, data: "{\"key\": \"value\"}", media_type: "application/json", filename: "data.json"}
        ],
        metadata: %{encoding: "utf8"}
      }
  """
  @spec user_with_file(String.t(), binary(), String.t(), String.t()) :: ReqLLM.Message.t()
  @spec user_with_file(String.t(), binary(), String.t(), String.t(), map()) :: ReqLLM.Message.t()
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
      {:ok, [%ReqLLM.Message{role: :user, content: "Hello"}, %ReqLLM.Message{role: :assistant, content: "Hi there"}]}

      # Invalid empty string
      iex> validate("")
      {:error, %ReqLLM.Error.Validation.Error{tag: :empty_prompt}}

  """
  @spec validate(String.t() | [ReqLLM.Message.t()] | t()) ::
          {:ok, String.t() | [ReqLLM.Message.t()]} | {:error, Error.t()}
  def validate(prompt) when is_binary(prompt) and prompt != "" do
    {:ok, prompt}
  end

  def validate(messages) when is_list(messages) do
    case validate_messages(messages) do
      :ok -> {:ok, messages}
      {:error, reason} -> {:error, Error.validation_error(:invalid_messages, reason)}
    end
  end

  # Accept wrapper transparently
  def validate(%__MODULE__{items: items}), do: validate(items)

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
      {:error, %ReqLLM.Error.Invalid.Message{reason: "Not a valid Message struct", index: 0}}

      iex> validate_messages("not a list")
      {:error, %ReqLLM.Error.Invalid.MessageList{reason: "Expected a list of messages", received: "not a list"}}
  """
  @spec validate_messages([ReqLLM.Message.t()] | t()) :: :ok | {:error, term()}
  def validate_messages(%__MODULE__{items: items}), do: validate_messages(items)

  def validate_messages(messages) when is_list(messages) do
    if Enum.empty?(messages) do
      {:error, ReqLLM.Error.Invalid.MessageList.exception(reason: "Message list cannot be empty")}
    else
      messages
      |> Enum.with_index()
      |> Enum.reduce_while(:ok, fn {message, index}, _acc ->
        case validate_message(message) do
          :ok ->
            {:cont, :ok}

          {:error, %{__struct__: _} = error} ->
            {:halt,
             {:error,
              ReqLLM.Error.Invalid.Message.exception(
                reason: Exception.message(error),
                index: index
              )}}
        end
      end)
    end
  end

  def validate_messages(messages) do
    {:error,
     ReqLLM.Error.Invalid.MessageList.exception(
       reason: "Expected a list of messages",
       received: messages
     )}
  end

  @doc """
  Validates that a single message is a valid Message struct.

  ## Examples

      iex> validate_message(user("Hello"))
      :ok

      iex> validate_message(%{role: :user, content: "Hello"})
      {:error, %ReqLLM.Error.Invalid.Message{reason: "Not a valid Message struct"}}

      iex> validate_message(nil)
      {:error, %ReqLLM.Error.Invalid.Message{reason: "Message cannot be nil"}}
  """
  @spec validate_message(ReqLLM.Message.t() | any()) :: :ok | {:error, term()}
  def validate_message(%Message{role: role, content: content} = _message) do
    with :ok <- validate_role(role) do
      validate_content(content)
    end
  end

  def validate_message(nil),
    do: {:error, ReqLLM.Error.Invalid.Message.exception(reason: "Message cannot be nil")}

  def validate_message(_),
    do: {:error, ReqLLM.Error.Invalid.Message.exception(reason: "Not a valid Message struct")}

  # Private validation helpers

  defp validate_role(:user), do: :ok
  defp validate_role(:assistant), do: :ok
  defp validate_role(:system), do: :ok
  defp validate_role(:tool), do: :ok

  defp validate_role(role),
    do: {:error, ReqLLM.Error.Invalid.Role.exception(role: role)}

  defp validate_content(content) when is_binary(content), do: :ok

  defp validate_content(content) when is_list(content) do
    if Enum.all?(content, &valid_content_part?/1) do
      :ok
    else
      {:error,
       ReqLLM.Error.Invalid.Content.exception(
         reason: "Content list contains invalid ContentPart structs",
         received: content
       )}
    end
  end

  defp validate_content(content),
    do:
      {:error,
       ReqLLM.Error.Invalid.Content.exception(
         reason: "Content must be a string or list of ContentPart structs",
         received: content
       )}

  defp valid_content_part?(%ContentPart{type: :text}), do: true
  defp valid_content_part?(%ContentPart{type: :image_url}), do: true
  defp valid_content_part?(%ContentPart{type: :image}), do: true
  defp valid_content_part?(%ContentPart{type: :file}), do: true
  defp valid_content_part?(%ContentPart{type: :tool_call}), do: true
  defp valid_content_part?(%ContentPart{type: :tool_result}), do: true
  defp valid_content_part?(_), do: false
end

# ---------------------------------------------------------------------------
# Protocol implementations
# ---------------------------------------------------------------------------

defimpl Enumerable, for: ReqLLM.Messages do
  def reduce(%ReqLLM.Messages{items: items}, acc, fun),
    do: Enumerable.List.reduce(items, acc, fun)

  def member?(%ReqLLM.Messages{items: items}, val),
    do: {:ok, Enum.member?(items, val)}

  def count(%ReqLLM.Messages{items: items}),
    do: {:ok, length(items)}

  def slice(%ReqLLM.Messages{items: items}) do
    size = length(items)
    {:ok, size, fn start, len, _step -> Enum.slice(items, start, len) end}
  end
end

defimpl Collectable, for: ReqLLM.Messages do
  def into(%ReqLLM.Messages{items: items}) do
    collector = fn
      acc, {:cont, x} -> [x | acc]
      acc, :done -> ReqLLM.Messages.new(Enum.reverse(acc) ++ items)
      _acc, :halt -> :ok
    end

    {[], collector}
  end
end
