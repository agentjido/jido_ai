defmodule Jido.AI.Message do
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
  - A list of `Jido.AI.ContentPart` structs for multi-modal content

  ## Examples

      # Simple text message
      %Jido.AI.Message{
        role: :user,
        content: "Hello, how are you?"
      }

      # System message with context
      %Jido.AI.Message{
        role: :system,
        content: "You are a helpful assistant."
      }

      # Multi-modal message with text and image
      %Jido.AI.Message{
        role: :user,
        content: [
          %Jido.AI.ContentPart{type: :text, text: "Describe this image:"},
          %Jido.AI.ContentPart{type: :image_url, url: "https://example.com/image.png"}
        ]
      }

      # Multi-modal message with text, image data, and file
      %Jido.AI.Message{
        role: :user,
        content: [
          %Jido.AI.ContentPart{type: :text, text: "Analyze this image and document:"},
          %Jido.AI.ContentPart{type: :image, data: image_binary, media_type: "image/png"},
          %Jido.AI.ContentPart{type: :file, data: pdf_binary, media_type: "application/pdf", filename: "doc.pdf"}
        ]
      }

      # Message with provider-specific options
      %Jido.AI.Message{
      role: :user,
      content: "Hello!",
      metadata: %{provider_options: %{openai: %{reasoning_effort: "low"}}}
      }

       # Assistant message with tool calls
       %Jido.AI.Message{
         role: :assistant,
         content: [
           %Jido.AI.ContentPart{type: :text, text: "I'll check the weather for you."},
           %Jido.AI.ContentPart{type: :tool_call, tool_call_id: "call_123", tool_name: "get_weather", input: %{location: "NYC"}}
         ]
       }

       # Tool result message
       %Jido.AI.Message{
         role: :tool,
         tool_call_id: "call_123",
         content: [
           %Jido.AI.ContentPart{type: :tool_result, tool_call_id: "call_123", tool_name: "get_weather", output: %{temperature: 72}}
         ]
       }

  """

  use TypedStruct

  alias Jido.AI.ContentPart

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

      iex> Jido.AI.Message.new(:user, "Hello")
      %Jido.AI.Message{role: :user, content: "Hello"}

      iex> Jido.AI.Message.new(:system, "You are helpful")
      %Jido.AI.Message{role: :system, content: "You are helpful"}

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
      ...>   Jido.AI.ContentPart.text("Describe this image:"),
      ...>   Jido.AI.ContentPart.image_url("https://example.com/image.png")
      ...> ]
      iex> Jido.AI.Message.user_multimodal(content)
      %Jido.AI.Message{role: :user, content: [%Jido.AI.ContentPart{type: :text, text: "Describe this image:"}, %Jido.AI.ContentPart{type: :image_url, url: "https://example.com/image.png"}]}

  """
  @spec user_multimodal([ContentPart.t()], keyword()) :: t()
  def user_multimodal(content_parts, opts \\ []) when is_list(content_parts) do
    new(:user, content_parts, opts)
  end

  @doc """
  Creates a new user message with text and an image URL.

  ## Examples

      iex> Jido.AI.Message.user_with_image("Describe this image:", "https://example.com/image.png")
      %Jido.AI.Message{role: :user, content: [%Jido.AI.ContentPart{type: :text, text: "Describe this image:"}, %Jido.AI.ContentPart{type: :image_url, url: "https://example.com/image.png"}]}

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
      ...>   Jido.AI.ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})
      ...> ]
      iex> Jido.AI.Message.assistant_with_tools("I'll check the weather.", tool_calls)
      %Jido.AI.Message{role: :assistant, content: [%Jido.AI.ContentPart{type: :text, text: "I'll check the weather."}, %Jido.AI.ContentPart{type: :tool_call, tool_call_id: "call_123", tool_name: "get_weather", input: %{location: "NYC"}}]}

  """
  @spec assistant_with_tools(String.t(), [ContentPart.t()], keyword()) :: t()
  def assistant_with_tools(text, tool_calls, opts \\ []) when is_binary(text) and is_list(tool_calls) do
    content = [ContentPart.text(text) | tool_calls]
    new(:assistant, content, opts)
  end

  @doc """
  Creates a tool result message.

  ## Examples

      iex> Jido.AI.Message.tool_result("call_123", "get_weather", %{temperature: 72})
      %Jido.AI.Message{role: :tool, tool_call_id: "call_123", content: [%Jido.AI.ContentPart{type: :tool_result, tool_call_id: "call_123", tool_name: "get_weather", output: %{temperature: 72}}]}

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

      iex> message = %Jido.AI.Message{role: :user, content: "Hello"}
      iex> Jido.AI.Message.valid?(message)
      true

      iex> Jido.AI.Message.valid?(%{role: :user, content: "Hello"})
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

      iex> message = %Jido.AI.Message{role: :user, content: "Hello", metadata: %{provider_options: %{openai: %{reasoning_effort: "low"}}}}
      iex> Jido.AI.Message.provider_options(message)
      %{openai: %{reasoning_effort: "low"}}

      iex> message = %Jido.AI.Message{role: :user, content: "Hello"}
      iex> Jido.AI.Message.provider_options(message)
      %{}

  """
  @spec provider_options(t()) :: map()
  def provider_options(%__MODULE__{metadata: nil}), do: %{}

  def provider_options(%__MODULE__{metadata: metadata}) do
    get_in(metadata, [:provider_options]) || %{}
  end
end
