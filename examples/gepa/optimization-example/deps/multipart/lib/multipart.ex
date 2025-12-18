defmodule Multipart do
  @moduledoc """
  `Multipart` constructs multipart messages.

  It aims to produce multipart messages that are compatible with [RFC
  2046](https://tools.ietf.org/html/rfc2046#section-5.1) for general use, and
  [RFC 7578](https://tools.ietf.org/html/rfc7578) for constructing
  `multipart/form-data` requests.
  """

  defstruct boundary: nil, parts: []

  @type t :: %__MODULE__{
          boundary: String.t(),
          parts: list(Multipart.Part.t())
        }

  @crlf "\r\n"
  @separator "--"

  alias Multipart.Part

  @doc """
  Create a new `Multipart` request.

  Pass in the boundary as the first argument to set it explicitly, otherwise
  it will default to a random 16 character alphanumeric string padded by `==`
  on either side.
  """
  @spec new(String.t()) :: t()
  def new(boundary \\ generate_boundary()) do
    %__MODULE__{boundary: boundary}
  end

  @doc """
  Adds a part to the `Multipart` message.
  """
  @spec add_part(t(), Multipart.Part.t()) :: t()
  def add_part(%__MODULE__{parts: parts} = multipart, %Part{} = part) do
    %__MODULE__{multipart | parts: parts ++ [part]}
  end

  @doc """
  Returns a `Stream` of the `Multipart` message body.
  """
  @spec body_stream(Multipart.t()) :: Enum.t()
  def body_stream(%__MODULE__{boundary: boundary, parts: parts}) do
    parts
    |> Enum.map(&part_stream(&1, boundary))
    |> Stream.concat()
    |> Stream.concat([final_delimiter(boundary)])
  end

  @doc """
  Returns a binary of the `Multipart` message body.

  This uses `body_stream/1` under the hood.
  """
  @spec body_binary(Multipart.t()) :: binary()
  def body_binary(%__MODULE__{} = multipart) do
    multipart
    |> body_stream()
    |> Enum.join("")
  end

  @doc """
  Returns the Content-Type header for the `Multipart` message.

      iex> multipart = Multipart.new("==abc123==")
      iex> Multipart.content_type(multipart, "multipart/mixed")
      "multipart/mixed; boundary=\\"==abc123==\\""
  """
  @spec content_type(Multipart.t(), String.t()) :: String.t()
  def content_type(%__MODULE__{boundary: boundary}, mime_type) do
    [mime_type, "boundary=\"#{boundary}\""]
    |> Enum.join("; ")
  end

  @doc """
  Returns the length of the `Multipart` message in bytes.

  It uses the `content_length` property in each of the message parts to
  calculate the length of the multipart message without reading the entire
  body into memory. `content_length` is set on the `Multipart.Part` by the
  constructor functions when possible, such as when the in-memory binary
  or the file on disk can be inspected.

  This will throw an error if any of the parts does not have `content_length`
  defined.
  """
  @spec content_length(Multipart.t()) :: pos_integer()
  def content_length(%__MODULE__{parts: parts, boundary: boundary}) do
    final_delimiter_length =
      final_delimiter(boundary)
      |> Enum.join("")
      |> byte_size()

    parts
    |> Enum.with_index()
    |> Enum.reduce(0, fn {%Part{} = part, index}, total ->
      case part_content_length(part, boundary) do
        cl when is_integer(cl) ->
          cl + total

        nil ->
          throw("Part at index #{index} has nil content_length")
      end
    end)
    |> Kernel.+(final_delimiter_length)
  end

  defp part_stream(%Part{} = part, boundary) do
    Stream.concat([part_delimiter(boundary), part_headers(part), part_body_stream(part)])
  end

  defp part_content_length(%Part{content_length: content_length} = part, boundary) do
    if is_integer(content_length) do
      Enum.concat(part_delimiter(boundary), part_headers(part))
      |> Enum.reduce(0, fn str, acc ->
        byte_size(str) + acc
      end)
      |> Kernel.+(content_length)
    else
      nil
    end
  end

  defp part_delimiter(boundary) do
    [@crlf, @separator, boundary, @crlf]
  end

  defp final_delimiter(boundary) do
    [@crlf, @separator, boundary, @separator, @crlf]
  end

  defp part_headers(%Part{headers: headers}) do
    headers
    |> Enum.flat_map(fn {k, v} ->
      ["#{k}: #{v}", @crlf]
    end)
    |> List.insert_at(-1, @crlf)
  end

  defp part_body_stream(%Part{body: body}) when is_binary(body) do
    [body]
  end

  defp part_body_stream(%Part{body: body}) when is_list(body) do
    body
  end

  defp part_body_stream(%Part{body: %type{} = body}) when type in [Stream, File.Stream] do
    body
  end

  defp generate_boundary() do
    token =
      16
      |> :crypto.strong_rand_bytes()
      |> Base.encode16(case: :lower)

    "==#{token}=="
  end
end
