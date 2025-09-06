defmodule ReqAI.Message do
  @moduledoc """
  Represents a single message in a conversation with an AI model.

  Messages are structured data objects that contain role information, content,
  and optional metadata for AI model interactions. This follows the Vercel AI SDK
  pattern for flexible prompt construction.

  ## Roles

  - `:user` - Messages from the user/human
  - `:assistant` - Messages from the AI assistant
  - `:system` - System prompts that set context or instructions
  - `:tool` - Messages containing tool execution results

  ## Content

  Content can be either:
  - A simple string for text-only messages
  - A list of `ReqAI.ContentPart` structs for multi-modal content

  ## Examples

      # Simple text message
      %ReqAI.Message{
        role: :user,
        content: "Hello, how are you?"
      }

      # System message with context
      %ReqAI.Message{
        role: :system,
        content: "You are a helpful assistant."
      }

      # Multi-modal message with text and image
      %ReqAI.Message{
        role: :user,
        content: [
          %ReqAI.ContentPart{type: :text, text: "Describe this image:"},
          %ReqAI.ContentPart{type: :image_url, url: "https://example.com/image.png"}
        ]
      }

      # Multi-modal message with text, image data, and file
      %ReqAI.Message{
        role: :user,
        content: [
          %ReqAI.ContentPart{type: :text, text: "Analyze this image and document:"},
          %ReqAI.ContentPart{type: :image, data: image_binary, media_type: "image/png"},
          %ReqAI.ContentPart{type: :file, data: pdf_binary, media_type: "application/pdf", filename: "doc.pdf"}
        ]
      }

      # Message with provider-specific options
      %ReqAI.Message{
      role: :user,
      content: "Hello!",
      metadata: %{provider_options: %{openai: %{reasoning_effort: "low"}}}
      }

       # Assistant message with tool calls
       %ReqAI.Message{
         role: :assistant,
         content: [
           %ReqAI.ContentPart{type: :text, text: "I'll check the weather for you."},
           %ReqAI.ContentPart{type: :tool_call, tool_call_id: "call_123", tool_name: "get_weather", input: %{location: "NYC"}}
         ]
       }

       # Tool result message
       %ReqAI.Message{
         role: :tool,
         tool_call_id: "call_123",
         content: [
           %ReqAI.ContentPart{type: :tool_result, tool_call_id: "call_123", tool_name: "get_weather", output: %{temperature: 72}}
         ]
       }

  """

  use TypedStruct

  alias ReqAI.ContentPart

  @type role :: :user | :assistant | :system | :tool

  typedstruct do
    @typedoc "A message in a conversation with an AI model"

    field(:role, role(), enforce: true)
    field(:content, String.t() | [ContentPart.t()], enforce: true)
    field(:name, String.t() | nil)
    field(:tool_call_id, String.t() | nil)
    field(:tool_calls, [map()] | nil)
    field(:metadata, map() | nil)
  end

  @doc """
  Creates a new message with the given role and content.

  ## Examples

      iex> ReqAI.Message.new(:user, "Hello")
      %ReqAI.Message{role: :user, content: "Hello"}

      iex> ReqAI.Message.new(:system, "You are helpful")
      %ReqAI.Message{role: :system, content: "You are helpful"}

  """
  @spec new(role(), String.t() | [ContentPart.t()], keyword()) :: t()
  def new(role, content, opts \\ []) do
    %__MODULE__{
      role: role,
      content: content,
      name: Keyword.get(opts, :name),
      tool_call_id: Keyword.get(opts, :tool_call_id),
      tool_calls: Keyword.get(opts, :tool_calls),
      metadata: Keyword.get(opts, :metadata)
    }
  end

  @doc """
  Creates a new user message with multi-modal content.

  ## Examples

      iex> content = [
      ...>   ReqAI.ContentPart.text("Describe this image:"),
      ...>   ReqAI.ContentPart.image_url("https://example.com/image.png")
      ...> ]
      iex> ReqAI.Message.user_multimodal(content)
      %ReqAI.Message{role: :user, content: [%ReqAI.ContentPart{type: :text, text: "Describe this image:"}, %ReqAI.ContentPart{type: :image_url, url: "https://example.com/image.png"}]}

  """
  @spec user_multimodal([ContentPart.t()], keyword()) :: t()
  def user_multimodal(content_parts, opts \\ []) when is_list(content_parts) do
    new(:user, content_parts, opts)
  end

  @doc """
  Creates a new user message with text and an image URL.

  ## Examples

      iex> ReqAI.Message.user_with_image("Describe this image:", "https://example.com/image.png")
      %ReqAI.Message{role: :user, content: [%ReqAI.ContentPart{type: :text, text: "Describe this image:"}, %ReqAI.ContentPart{type: :image_url, url: "https://example.com/image.png"}]}

  """
  @spec user_with_image(String.t(), String.t(), keyword()) :: t()
  def user_with_image(text, image_url, opts \\ []) do
    content = [
      ContentPart.text(text),
      ContentPart.image_url(image_url)
    ]

    new(:user, content, opts)
  end

  @doc """
  Creates an assistant message with tool calls.

  ## Examples

      iex> tool_calls = [
      ...>   ReqAI.ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})
      ...> ]
      iex> ReqAI.Message.assistant_with_tools("I'll check the weather.", tool_calls)
      %ReqAI.Message{role: :assistant, content: [%ReqAI.ContentPart{type: :text, text: "I'll check the weather."}, %ReqAI.ContentPart{type: :tool_call, tool_call_id: "call_123", tool_name: "get_weather", input: %{location: "NYC"}}]}

  """
  @spec assistant_with_tools(String.t(), [ContentPart.t()], keyword()) :: t()
  def assistant_with_tools(text, tool_calls, opts \\ []) when is_binary(text) and is_list(tool_calls) do
    content = [ContentPart.text(text) | tool_calls]
    new(:assistant, content, opts)
  end

  @doc """
  Creates a tool result message.

  ## Examples

      iex> ReqAI.Message.tool_result("call_123", "get_weather", %{temperature: 72})
      %ReqAI.Message{role: :tool, tool_call_id: "call_123", content: [%ReqAI.ContentPart{type: :tool_result, tool_call_id: "call_123", tool_name: "get_weather", output: %{temperature: 72}}]}

  """
  @spec tool_result(String.t(), String.t(), any(), keyword()) :: t()
  def tool_result(tool_call_id, tool_name, output, opts \\ []) when is_binary(tool_call_id) and is_binary(tool_name) do
    content = [ContentPart.tool_result(tool_call_id, tool_name, output)]

    new(:tool, content, Keyword.put(opts, :tool_call_id, tool_call_id))
  end

  @doc """
  Validates a message struct.

  Ensures the message has valid role and content fields.

  ## Examples

      iex> message = %ReqAI.Message{role: :user, content: "Hello"}
      iex> ReqAI.Message.valid?(message)
      true

      iex> ReqAI.Message.valid?(%{role: :user, content: "Hello"})
      false

  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{role: role, content: content, tool_call_id: tool_call_id})
      when role in [:user, :assistant, :system, :tool] do
    content_valid? =
      case content do
        content when is_binary(content) and content != "" ->
          true

        content when is_list(content) and content != [] ->
          Enum.all?(content, &ContentPart.valid?/1)

        _ ->
          false
      end

    # Tool role messages must have a tool_call_id
    tool_valid? =
      case role do
        :tool when is_binary(tool_call_id) and tool_call_id != "" -> true
        :tool -> false
        _ -> true
      end

    content_valid? and tool_valid?
  end

  def valid?(_), do: false

  @doc """
  Gets provider-specific options from message metadata.

  ## Examples

      iex> message = %ReqAI.Message{role: :user, content: "Hello", metadata: %{provider_options: %{openai: %{reasoning_effort: "low"}}}}
      iex> ReqAI.Message.provider_options(message)
      %{openai: %{reasoning_effort: "low"}}

      iex> message = %ReqAI.Message{role: :user, content: "Hello"}
      iex> ReqAI.Message.provider_options(message)
      %{}

  """
  @spec provider_options(t()) :: map()
  def provider_options(%__MODULE__{metadata: nil}), do: %{}

  def provider_options(%__MODULE__{metadata: metadata}) do
    get_in(metadata, [:provider_options]) || %{}
  end
end

# Implement Enumerable protocol so Message can be treated as a single-item collection
defimpl Enumerable, for: ReqAI.Message do
  def count(_message), do: {:ok, 1}
  
  def member?(_message, _element), do: {:error, __MODULE__}
  
  def slice(_message), do: {:error, __MODULE__}
  
  def reduce(message, {:cont, acc}, fun) do
    fun.(message, acc)
  end
  
  def reduce(_message, {:halt, acc}, _fun) do
    {:halted, acc}
  end
  
  def reduce(message, {:suspend, acc}, fun) do
    {:suspended, acc, &reduce(message, &1, fun)}
  end
end
