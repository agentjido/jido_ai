defmodule ReqAI.MessageBuilder do
  @moduledoc """
  Fluent builder for constructing ReqAI.Message structs with multi-modal content.

  The MessageBuilder provides a chainable API to construct complex messages without
  the combinatorial explosion of helper functions. It supports all content types
  and message configurations.

  ## Examples

      # Simple text message
      Message.build()
      |> Message.role(:user)
      |> Message.text("Hello, world!")
      |> Message.create()

      # Multi-modal message with image
      Message.build()
      |> Message.role(:user)
      |> Message.text("Describe this image:")
      |> Message.image_url("https://example.com/image.png")
      |> Message.create()

      # Complex multi-modal message
      Message.build()
      |> Message.role(:user)
      |> Message.text("Analyze these files:")
      |> Message.image_data(image_binary, "image/png")
      |> Message.file(pdf_data, "application/pdf", "report.pdf")
      |> Message.metadata(%{provider_options: %{openai: %{detail: "high"}}})
      |> Message.create()

      # Assistant message with tool calls
      Message.build()
      |> Message.role(:assistant)
      |> Message.text("I'll help you with that.")
      |> Message.tool_call("call_123", "get_weather", %{location: "NYC"})
      |> Message.create()

      # Tool result message
      Message.build()
      |> Message.role(:tool)
      |> Message.tool_call_id("call_123")
      |> Message.tool_result("call_123", "get_weather", %{temperature: 72})
      |> Message.create()

  """

  alias ReqAI.{Message, ContentPart}

  defstruct role: nil,
            content_parts: [],
            name: nil,
            tool_call_id: nil,
            tool_calls: nil,
            metadata: nil

  @type t :: %__MODULE__{
          role: Message.role() | nil,
          content_parts: [ContentPart.t()],
          name: String.t() | nil,
          tool_call_id: String.t() | nil,
          tool_calls: [map()] | nil,
          metadata: map() | nil
        }

  @doc """
  Creates a new MessageBuilder instance.

  ## Examples

      iex> ReqAI.MessageBuilder.new()
      %ReqAI.MessageBuilder{role: nil, content_parts: []}

  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Sets the role for the message.

  ## Examples

      iex> ReqAI.MessageBuilder.new() |> ReqAI.MessageBuilder.role(:user)
      %ReqAI.MessageBuilder{role: :user, content_parts: []}

  """
  @spec role(t(), Message.role()) :: t()
  def role(%__MODULE__{} = builder, role) when role in [:user, :assistant, :system, :tool] do
    %{builder | role: role}
  end

  @doc """
  Adds text content to the message.

  ## Examples

      iex> builder = ReqAI.MessageBuilder.new() |> ReqAI.MessageBuilder.text("Hello")
      iex> length(builder.content_parts)
      1
      iex> [part] = builder.content_parts
      iex> part.type
      :text

  """
  @spec text(t(), String.t(), keyword()) :: t()
  def text(%__MODULE__{} = builder, text, opts \\ []) when is_binary(text) do
    part = ContentPart.text(text, opts)
    %{builder | content_parts: builder.content_parts ++ [part]}
  end

  @doc """
  Adds an image URL content part to the message.

  ## Examples

      iex> builder = ReqAI.MessageBuilder.new() |> ReqAI.MessageBuilder.image_url("https://example.com/image.png")
      iex> [part] = builder.content_parts
      iex> part.type
      :image_url

  """
  @spec image_url(t(), String.t(), keyword()) :: t()
  def image_url(%__MODULE__{} = builder, url, opts \\ []) when is_binary(url) do
    part = ContentPart.image_url(url, opts)
    %{builder | content_parts: builder.content_parts ++ [part]}
  end

  @doc """
  Adds an image data content part to the message.

  ## Examples

      iex> image_data = <<137, 80, 78, 71>>
      iex> builder = ReqAI.MessageBuilder.new() |> ReqAI.MessageBuilder.image_data(image_data, "image/png")
      iex> [part] = builder.content_parts
      iex> part.type
      :image

  """
  @spec image_data(t(), binary(), String.t(), keyword()) :: t()
  def image_data(%__MODULE__{} = builder, data, media_type, opts \\ [])
      when is_binary(data) and is_binary(media_type) do
    part = ContentPart.image_data(data, media_type, opts)
    %{builder | content_parts: builder.content_parts ++ [part]}
  end

  @doc """
  Adds a file content part to the message.

  ## Examples

      iex> file_data = <<37, 80, 68, 70>>
      iex> builder = ReqAI.MessageBuilder.new() |> ReqAI.MessageBuilder.file(file_data, "application/pdf", "doc.pdf")
      iex> [part] = builder.content_parts
      iex> part.type
      :file

  """
  @spec file(t(), binary(), String.t(), String.t(), keyword()) :: t()
  def file(%__MODULE__{} = builder, data, media_type, filename, opts \\ [])
      when is_binary(data) and is_binary(media_type) and is_binary(filename) do
    part = ContentPart.file(data, media_type, filename, opts)
    %{builder | content_parts: builder.content_parts ++ [part]}
  end

  @doc """
  Adds a tool call content part to the message.

  ## Examples

      iex> builder = ReqAI.MessageBuilder.new() |> ReqAI.MessageBuilder.tool_call("call_123", "get_weather", %{location: "NYC"})
      iex> [part] = builder.content_parts
      iex> part.type
      :tool_call

  """
  @spec tool_call(t(), String.t(), String.t(), map(), keyword()) :: t()
  def tool_call(%__MODULE__{} = builder, tool_call_id, tool_name, input, opts \\ [])
      when is_binary(tool_call_id) and is_binary(tool_name) and is_map(input) do
    part = ContentPart.tool_call(tool_call_id, tool_name, input, opts)
    %{builder | content_parts: builder.content_parts ++ [part]}
  end

  @doc """
  Adds a tool result content part to the message.

  ## Examples

      iex> builder = ReqAI.MessageBuilder.new() |> ReqAI.MessageBuilder.tool_result("call_123", "get_weather", %{temp: 72})
      iex> [part] = builder.content_parts
      iex> part.type
      :tool_result

  """
  @spec tool_result(t(), String.t(), String.t(), any(), keyword()) :: t()
  def tool_result(%__MODULE__{} = builder, tool_call_id, tool_name, output, opts \\ [])
      when is_binary(tool_call_id) and is_binary(tool_name) do
    part = ContentPart.tool_result(tool_call_id, tool_name, output, opts)
    %{builder | content_parts: builder.content_parts ++ [part]}
  end

  @doc """
  Sets the name field for the message.

  ## Examples

      iex> builder = ReqAI.MessageBuilder.new() |> ReqAI.MessageBuilder.name("assistant")
      iex> builder.name
      "assistant"

  """
  @spec name(t(), String.t()) :: t()
  def name(%__MODULE__{} = builder, name) when is_binary(name) do
    %{builder | name: name}
  end

  @doc """
  Sets the tool_call_id field for the message (required for tool role messages).

  ## Examples

      iex> builder = ReqAI.MessageBuilder.new() |> ReqAI.MessageBuilder.tool_call_id("call_123")
      iex> builder.tool_call_id
      "call_123"

  """
  @spec tool_call_id(t(), String.t()) :: t()
  def tool_call_id(%__MODULE__{} = builder, tool_call_id) when is_binary(tool_call_id) do
    %{builder | tool_call_id: tool_call_id}
  end

  @doc """
  Sets the tool_calls field for the message.

  ## Examples

      iex> calls = [%{id: "call_123", function: %{name: "get_weather"}}]
      iex> builder = ReqAI.MessageBuilder.new() |> ReqAI.MessageBuilder.tool_calls(calls)
      iex> builder.tool_calls
      [%{id: "call_123", function: %{name: "get_weather"}}]

  """
  @spec tool_calls(t(), [map()]) :: t()
  def tool_calls(%__MODULE__{} = builder, tool_calls) when is_list(tool_calls) do
    %{builder | tool_calls: tool_calls}
  end

  @doc """
  Sets metadata for the message.

  ## Examples

      iex> meta = %{provider_options: %{openai: %{detail: "high"}}}
      iex> builder = ReqAI.MessageBuilder.new() |> ReqAI.MessageBuilder.metadata(meta)
      iex> builder.metadata
      %{provider_options: %{openai: %{detail: "high"}}}

  """
  @spec metadata(t(), map()) :: t()
  def metadata(%__MODULE__{} = builder, metadata) when is_map(metadata) do
    %{builder | metadata: metadata}
  end

  @doc """
  Merges additional metadata into existing metadata.

  ## Examples

      iex> builder = ReqAI.MessageBuilder.new() 
      ...>   |> ReqAI.MessageBuilder.metadata(%{a: 1}) 
      ...>   |> ReqAI.MessageBuilder.merge_metadata(%{b: 2})
      iex> builder.metadata
      %{a: 1, b: 2}

  """
  @spec merge_metadata(t(), map()) :: t()
  def merge_metadata(%__MODULE__{metadata: nil} = builder, new_metadata)
      when is_map(new_metadata) do
    %{builder | metadata: new_metadata}
  end

  def merge_metadata(%__MODULE__{metadata: existing} = builder, new_metadata)
      when is_map(existing) and is_map(new_metadata) do
    %{builder | metadata: Map.merge(existing, new_metadata)}
  end

  @doc """
  Creates the final Message struct from the builder.

  Returns `{:ok, message}` if the builder state is valid, or `{:error, reason}` if invalid.

  ## Examples

      iex> {:ok, message} = ReqAI.MessageBuilder.new()
      ...>   |> ReqAI.MessageBuilder.role(:user)
      ...>   |> ReqAI.MessageBuilder.text("Hello")
      ...>   |> ReqAI.MessageBuilder.create()
      iex> message.role
      :user

  """
  @spec create(t()) :: {:ok, Message.t()} | {:error, String.t()}
  def create(%__MODULE__{role: nil}) do
    {:error, "Role is required"}
  end

  def create(%__MODULE__{content_parts: []}) do
    {:error, "Content is required"}
  end

  def create(%__MODULE__{role: :tool, tool_call_id: nil}) do
    {:error, "tool_call_id is required for tool role messages"}
  end

  def create(%__MODULE__{} = builder) do
    content =
      case builder.content_parts do
        [%ContentPart{type: :text, text: text}] -> text
        parts -> parts
      end

    message = %Message{
      role: builder.role,
      content: content,
      name: builder.name,
      tool_call_id: builder.tool_call_id,
      tool_calls: builder.tool_calls,
      metadata: builder.metadata
    }

    if Message.valid?(message) do
      {:ok, message}
    else
      {:error, "Invalid message structure"}
    end
  end

  @doc """
  Creates the final Message struct from the builder, raising on error.

  ## Examples

      iex> message = ReqAI.MessageBuilder.new()
      ...>   |> ReqAI.MessageBuilder.role(:user)
      ...>   |> ReqAI.MessageBuilder.text("Hello")
      ...>   |> ReqAI.MessageBuilder.create!()
      iex> message.role
      :user

  """
  @spec create!(t()) :: Message.t()
  def create!(%__MODULE__{} = builder) do
    case create(builder) do
      {:ok, message} -> message
      {:error, reason} -> raise ArgumentError, "Failed to create message: #{reason}"
    end
  end
end
