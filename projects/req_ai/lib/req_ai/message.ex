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

  alias ReqAI.{ContentPart, MessageBuilder}

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

  # Builder Pattern API

  @doc """
  Starts building a new message using the builder pattern.

  ## Examples

      iex> ReqAI.Message.build() |> ReqAI.Message.role(:user) |> ReqAI.Message.text("Hello") |> ReqAI.Message.create!()
      %ReqAI.Message{role: :user, content: "Hello"}

      iex> message = ReqAI.Message.build()
      ...>   |> ReqAI.Message.role(:user)
      ...>   |> ReqAI.Message.text("Describe this:")
      ...>   |> ReqAI.Message.image_url("https://example.com/image.png")
      ...>   |> ReqAI.Message.create!()
      iex> message.role
      :user

  """
  @spec build() :: MessageBuilder.t()
  def build, do: MessageBuilder.new()

  @doc """
  Sets the role for the message being built.
  """
  @spec role(MessageBuilder.t(), role()) :: MessageBuilder.t()
  def role(%MessageBuilder{} = builder, role), do: MessageBuilder.role(builder, role)

  @doc """
  Adds text content to the message being built.
  """
  @spec text(MessageBuilder.t(), String.t(), keyword()) :: MessageBuilder.t()
  def text(%MessageBuilder{} = builder, text, opts \\ []),
    do: MessageBuilder.text(builder, text, opts)

  @doc """
  Adds an image URL content part to the message being built.
  """
  @spec image_url(MessageBuilder.t(), String.t(), keyword()) :: MessageBuilder.t()
  def image_url(%MessageBuilder{} = builder, url, opts \\ []),
    do: MessageBuilder.image_url(builder, url, opts)

  @doc """
  Adds an image data content part to the message being built.
  """
  @spec image_data(MessageBuilder.t(), binary(), String.t(), keyword()) :: MessageBuilder.t()
  def image_data(%MessageBuilder{} = builder, data, media_type, opts \\ []),
    do: MessageBuilder.image_data(builder, data, media_type, opts)

  @doc """
  Adds a file content part to the message being built.
  """
  @spec file(MessageBuilder.t(), binary(), String.t(), String.t(), keyword()) ::
          MessageBuilder.t()
  def file(%MessageBuilder{} = builder, data, media_type, filename, opts \\ []),
    do: MessageBuilder.file(builder, data, media_type, filename, opts)

  @doc """
  Adds a tool call content part to the message being built.
  """
  @spec tool_call(MessageBuilder.t(), String.t(), String.t(), map(), keyword()) ::
          MessageBuilder.t()
  def tool_call(%MessageBuilder{} = builder, tool_call_id, tool_name, input, opts \\ []),
    do: MessageBuilder.tool_call(builder, tool_call_id, tool_name, input, opts)

  @doc """
  Adds a tool result content part to the message being built.
  """
  @spec tool_result(MessageBuilder.t(), String.t(), String.t(), any(), keyword()) ::
          MessageBuilder.t()
  def tool_result(%MessageBuilder{} = builder, tool_call_id, tool_name, output, opts),
    do: MessageBuilder.tool_result(builder, tool_call_id, tool_name, output, opts)

  @doc """
  Sets the name field for the message being built.
  """
  @spec name(MessageBuilder.t(), String.t()) :: MessageBuilder.t()
  def name(%MessageBuilder{} = builder, name), do: MessageBuilder.name(builder, name)

  @doc """
  Sets the tool_call_id field for the message being built.
  """
  @spec tool_call_id(MessageBuilder.t(), String.t()) :: MessageBuilder.t()
  def tool_call_id(%MessageBuilder{} = builder, tool_call_id),
    do: MessageBuilder.tool_call_id(builder, tool_call_id)

  @doc """
  Sets metadata for the message being built.
  """
  @spec metadata(MessageBuilder.t(), map()) :: MessageBuilder.t()
  def metadata(%MessageBuilder{} = builder, metadata),
    do: MessageBuilder.metadata(builder, metadata)

  @doc """
  Creates the final Message struct from the builder.
  """
  @spec create(MessageBuilder.t()) :: {:ok, t()} | {:error, String.t()}
  def create(%MessageBuilder{} = builder), do: MessageBuilder.create(builder)

  @doc """
  Creates the final Message struct from the builder, raising on error.
  """
  @spec create!(MessageBuilder.t()) :: t()
  def create!(%MessageBuilder{} = builder), do: MessageBuilder.create!(builder)

  # Direct Constructor (preserved for backward compatibility)

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
  def assistant_with_tools(text, tool_calls, opts \\ [])
      when is_binary(text) and is_list(tool_calls) do
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
  def tool_result(tool_call_id, tool_name, output, opts \\ [])
      when is_binary(tool_call_id) and is_binary(tool_name) do
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

# Implement Enumerable protocol to iterate over content parts
defimpl Enumerable, for: ReqAI.Message do
  alias ReqAI.ContentPart

  def count(%ReqAI.Message{content: content}) when is_list(content), do: {:ok, length(content)}
  def count(%ReqAI.Message{content: content}) when is_binary(content), do: {:ok, 1}

  def member?(%ReqAI.Message{content: content}, element) when is_list(content) do
    {:ok, Enum.member?(content, element)}
  end

  def member?(%ReqAI.Message{content: content}, element) when is_binary(content) do
    {:ok, content == element}
  end

  def slice(%ReqAI.Message{content: content}) when is_list(content) do
    size = length(content)
    {:ok, size, fn start, length, _step -> Enum.slice(content, start, length) end}
  end

  def slice(%ReqAI.Message{content: content}) when is_binary(content) do
    {:ok, 1,
     fn start, length, _step ->
       if start == 0 and length > 0, do: [content], else: []
     end}
  end

  def reduce(%ReqAI.Message{content: content}, acc, fun) when is_list(content) do
    Enumerable.List.reduce(content, acc, fun)
  end

  def reduce(%ReqAI.Message{content: content}, {:cont, acc}, fun) when is_binary(content) do
    fun.(content, acc)
  end

  def reduce(%ReqAI.Message{content: _content}, {:halt, acc}, _fun) do
    {:halted, acc}
  end

  def reduce(%ReqAI.Message{content: content} = message, {:suspend, acc}, fun)
      when is_binary(content) do
    {:suspended, acc, &reduce(message, &1, fun)}
  end
end
