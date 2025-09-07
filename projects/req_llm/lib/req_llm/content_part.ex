defmodule ReqLLM.ContentPart do
  @moduledoc """
  Represents a piece of content within a message for multi-modal AI interactions.

  ContentPart supports different types of content that can be included in messages.
  For Iteration 1, only text content is supported. Future iterations will add
  support for images, files, tool calls, and other content types.

  ## Content Types

  - `:text` - Plain text content with a `text` field
  - `:image_url` - Image content referenced by URL with a `url` field
  - `:image` - Binary image data with `data` and `media_type` fields
  - `:file` - File attachments with `data`, `media_type`, and `filename` fields
  - `:tool_call` - Tool call content with `tool_call_id`, `tool_name`, and `input` fields
  - `:tool_result` - Tool result content with `tool_call_id`, `tool_name`, and `output` fields

  ## Examples

      # Text content part
      %ReqLLM.ContentPart{
        type: :text,
        text: "Hello, world!"
      }

      # Image URL content part
      %ReqLLM.ContentPart{
        type: :image_url,
        url: "https://example.com/image.png"
      }

      # Image data content part
      %ReqLLM.ContentPart{
        type: :image,
        data: <<...binary_data...>>,
        media_type: "image/png"
      }

      # File content part
      %ReqLLM.ContentPart{
        type: :file,
        data: <<...binary_data...>>,
        media_type: "application/pdf",
        filename: "document.pdf"
      }

       # Tool call content part
       %ReqLLM.ContentPart{
         type: :tool_call,
         tool_call_id: "call_123",
         tool_name: "get_weather",
         input: %{location: "NYC"}
       }

       # Tool result content part
       %ReqLLM.ContentPart{
         type: :tool_result,
         tool_call_id: "call_123",
         tool_name: "get_weather",
         output: %{temperature: 72, unit: "fahrenheit"}
       }

  """

  use TypedStruct

  @type content_type :: :text | :image_url | :image | :file | :tool_call | :tool_result

  typedstruct do
    @typedoc "A piece of content within a message"

    field(:type, content_type(), enforce: true)

    # Text content fields
    field(:text, String.t() | nil)

    # Image/file content fields
    field(:url, String.t() | nil)
    field(:data, binary() | nil)
    field(:media_type, String.t() | nil)
    field(:filename, String.t() | nil)

    # Tool content fields
    field(:tool_call_id, String.t() | nil)
    field(:tool_name, String.t() | nil)
    field(:input, map() | nil)
    field(:output, any() | nil)

    # Metadata for provider-specific options at content part level
    field(:metadata, map() | nil)
  end

  @doc """
  Creates a new text content part.

  ## Examples

      iex> ReqLLM.ContentPart.text("Hello, world!")
      %ReqLLM.ContentPart{type: :text, text: "Hello, world!"}

      iex> ReqLLM.ContentPart.text("Hello, world!", metadata: %{provider_options: %{openai: %{image_detail: "high"}}})
      %ReqLLM.ContentPart{type: :text, text: "Hello, world!", metadata: %{provider_options: %{openai: %{image_detail: "high"}}}}

  """
  @spec text(String.t(), keyword()) :: t()
  def text(text, opts \\ []) when is_binary(text) do
    %__MODULE__{
      type: :text,
      text: text,
      metadata: Keyword.get(opts, :metadata)
    }
  end

  @doc """
  Creates a new image URL content part.

  ## Examples

      iex> ReqLLM.ContentPart.image_url("https://example.com/image.png")
      %ReqLLM.ContentPart{type: :image_url, url: "https://example.com/image.png"}

      iex> ReqLLM.ContentPart.image_url("https://example.com/image.png", metadata: %{provider_options: %{openai: %{detail: "high"}}})
      %ReqLLM.ContentPart{type: :image_url, url: "https://example.com/image.png", metadata: %{provider_options: %{openai: %{detail: "high"}}}}

  """
  @spec image_url(String.t(), keyword()) :: t()
  def image_url(url, opts \\ []) when is_binary(url) do
    %__MODULE__{
      type: :image_url,
      url: url,
      metadata: Keyword.get(opts, :metadata)
    }
  end

  @doc """
  Creates a new image data content part.

  ## Examples

      iex> image_data = <<137, 80, 78, 71>>
      iex> ReqLLM.ContentPart.image_data(image_data, "image/png")
      %ReqLLM.ContentPart{type: :image, data: <<137, 80, 78, 71>>, media_type: "image/png"}

  """
  @spec image_data(binary(), String.t(), keyword()) :: t()
  def image_data(data, media_type, opts \\ []) when is_binary(data) and is_binary(media_type) do
    %__MODULE__{
      type: :image,
      data: data,
      media_type: media_type,
      metadata: Keyword.get(opts, :metadata)
    }
  end

  @doc """
  Creates a new file content part.

  ## Examples

      iex> file_data = <<37, 80, 68, 70>>
      iex> ReqLLM.ContentPart.file(file_data, "application/pdf", "document.pdf")
      %ReqLLM.ContentPart{type: :file, data: <<37, 80, 68, 70>>, media_type: "application/pdf", filename: "document.pdf"}

  """
  @spec file(binary(), String.t(), String.t(), keyword()) :: t()
  def file(data, media_type, filename, opts \\ [])
      when is_binary(data) and is_binary(media_type) and is_binary(filename) do
    %__MODULE__{
      type: :file,
      data: data,
      media_type: media_type,
      filename: filename,
      metadata: Keyword.get(opts, :metadata)
    }
  end

  @doc """
  Creates a new tool call content part.

  ## Examples

      iex> ReqLLM.ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})
      %ReqLLM.ContentPart{type: :tool_call, tool_call_id: "call_123", tool_name: "get_weather", input: %{location: "NYC"}}

  """
  @spec tool_call(String.t(), String.t(), map(), keyword()) :: t()
  def tool_call(tool_call_id, tool_name, input, opts \\ [])
      when is_binary(tool_call_id) and is_binary(tool_name) and is_map(input) do
    %__MODULE__{
      type: :tool_call,
      tool_call_id: tool_call_id,
      tool_name: tool_name,
      input: input,
      metadata: Keyword.get(opts, :metadata)
    }
  end

  @doc """
  Creates a new tool result content part.

  ## Examples

      iex> ReqLLM.ContentPart.tool_result("call_123", "get_weather", %{temperature: 72})
      %ReqLLM.ContentPart{type: :tool_result, tool_call_id: "call_123", tool_name: "get_weather", output: %{temperature: 72}}

  """
  @spec tool_result(String.t(), String.t(), any(), keyword()) :: t()
  def tool_result(tool_call_id, tool_name, output, opts \\ [])
      when is_binary(tool_call_id) and is_binary(tool_name) do
    %__MODULE__{
      type: :tool_result,
      tool_call_id: tool_call_id,
      tool_name: tool_name,
      output: output,
      metadata: Keyword.get(opts, :metadata)
    }
  end

  @doc """
  Validates a content part struct.

  Ensures the content part has a valid type and appropriate fields for that type.

  ## Examples

      iex> part = ReqLLM.ContentPart.text("Hello")
      iex> ReqLLM.ContentPart.valid?(part)
      true

      iex> part = ReqLLM.ContentPart.image_url("https://example.com/image.png")
      iex> ReqLLM.ContentPart.valid?(part)
      true

      iex> ReqLLM.ContentPart.valid?(%{type: :text, text: "Hello"})
      false

  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{type: :text, text: text}) when is_binary(text) and text != "", do: true

  def valid?(%__MODULE__{type: :image_url, url: url}) when is_binary(url) and url != "" do
    valid_url?(url)
  end

  def valid?(%__MODULE__{type: :image, data: data, media_type: media_type})
      when is_binary(data) and data != <<>> and is_binary(media_type) and media_type != "" do
    valid_image_media_type?(media_type)
  end

  def valid?(%__MODULE__{type: :file, data: data, media_type: media_type, filename: filename})
      when is_binary(data) and data != <<>> and is_binary(media_type) and media_type != "" and
             is_binary(filename) and
             filename != "" do
    valid_media_type?(media_type)
  end

  def valid?(%__MODULE__{
        type: :tool_call,
        tool_call_id: tool_call_id,
        tool_name: tool_name,
        input: input
      })
      when is_binary(tool_call_id) and tool_call_id != "" and is_binary(tool_name) and
             tool_name != "" and is_map(input) do
    true
  end

  def valid?(%__MODULE__{
        type: :tool_result,
        tool_call_id: tool_call_id,
        tool_name: tool_name,
        output: output
      })
      when is_binary(tool_call_id) and tool_call_id != "" and is_binary(tool_name) and
             tool_name != "" and
             not is_nil(output) do
    true
  end

  def valid?(_), do: false

  @doc """
  Gets provider-specific options from content part metadata.

  ## Examples

      iex> part = ReqLLM.ContentPart.text("Hello", metadata: %{provider_options: %{openai: %{image_detail: "high"}}})
      iex> ReqLLM.ContentPart.provider_options(part)
      %{openai: %{image_detail: "high"}}

      iex> part = ReqLLM.ContentPart.text("Hello")
      iex> ReqLLM.ContentPart.provider_options(part)
      %{}

  """
  @spec provider_options(t()) :: map()
  def provider_options(%__MODULE__{metadata: nil}), do: %{}

  def provider_options(%__MODULE__{metadata: metadata}) do
    get_in(metadata, [:provider_options]) || %{}
  end

  @doc """
  Converts a content part to a map suitable for API requests.

  ## Examples

      iex> part = ReqLLM.ContentPart.text("Hello")
      iex> ReqLLM.ContentPart.to_map(part)
      %{type: "text", text: "Hello"}

      iex> part = ReqLLM.ContentPart.image_url("https://example.com/image.png")
      iex> ReqLLM.ContentPart.to_map(part)
      %{type: "image_url", image_url: %{url: "https://example.com/image.png"}}

  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{type: :text, text: text}) do
    %{type: "text", text: text}
  end

  def to_map(%__MODULE__{type: :image_url, url: url}) do
    %{type: "image_url", image_url: %{url: url}}
  end

  def to_map(%__MODULE__{type: :image, data: data, media_type: media_type}) do
    # Encode binary data as base64 for API requests
    base64_data = Base.encode64(data)
    data_url = "data:#{media_type};base64,#{base64_data}"
    %{type: "image_url", image_url: %{url: data_url}}
  end

  def to_map(%__MODULE__{type: :file, data: data, media_type: media_type, filename: filename}) do
    # For files, we'll return a structured format - providers can interpret this as needed
    base64_data = Base.encode64(data)

    %{
      type: "file",
      file: %{
        data: base64_data,
        media_type: media_type,
        filename: filename
      }
    }
  end

  def to_map(%__MODULE__{
        type: :tool_call,
        tool_call_id: tool_call_id,
        tool_name: tool_name,
        input: input
      }) do
    %{
      type: "tool_call",
      id: tool_call_id,
      function: %{
        name: tool_name,
        arguments: Jason.encode!(input)
      }
    }
  end

  def to_map(%__MODULE__{
        type: :tool_result,
        tool_call_id: tool_call_id,
        tool_name: tool_name,
        output: output
      }) do
    %{
      type: "tool_result",
      tool_call_id: tool_call_id,
      name: tool_name,
      content: Jason.encode!(output)
    }
  end

  # Private helper functions

  defp valid_url?(url) do
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] and not is_nil(uri.host)
  end

  defp valid_image_media_type?(media_type) do
    media_type in [
      "image/png",
      "image/jpeg",
      "image/jpg",
      "image/gif",
      "image/bmp",
      "image/webp",
      "image/svg+xml"
    ]
  end

  defp valid_media_type?(media_type) do
    # Allow any media type that follows the pattern type/subtype
    case String.split(media_type, "/", parts: 2) do
      [type, subtype] when type != "" and subtype != "" -> true
      _ -> false
    end
  end
end
