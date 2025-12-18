defmodule Multipart.Part do
  @moduledoc """
  Represents an individual part of a `Multipart` message.
  """
  defstruct headers: [], body: nil, content_length: nil

  @type body :: binary() | Enum.t()

  @type t :: %__MODULE__{
          headers: [],
          body: body,
          content_length: pos_integer() | nil
        }

  @type headers :: [{binary, binary}]
  @type name :: String.t() | atom()

  @doc """
  Builds a `Part` with a binary body.

  Set the `content_length` of the `Part` to the length of the binary.
  """
  @spec binary_body(binary(), headers()) :: t()
  def binary_body(body, headers \\ []) when is_binary(body) do
    content_length = byte_size(body)
    %__MODULE__{body: body, content_length: content_length, headers: headers}
  end

  @doc """
  Builds a `Part` with a streaming file body.

  Set the `content_length` of the `Part` to the size of the file on disk, as
  inspected with `File.stat`.
  """
  @spec file_body(String.t(), headers()) :: t()
  def file_body(path, headers \\ []) do
    %File.Stat{size: size} = File.stat!(path)
    file_stream = File.stream!(path, [{:read_ahead, 4096}], 1024)

    %__MODULE__{body: file_stream, content_length: size, headers: headers}
  end

  @doc """
  Builds a `Part` with a `Stream` body.

  Because the length of the `Stream` cannot be known up front it doesn't
  define the `content_length`. This will cause `Multipart.content_length/1`
  to error unless you set the `content_length` manually in the struct.
  """
  @spec stream_body(Enum.t(), headers()) :: t()
  def stream_body(stream, headers \\ []) do
    %__MODULE__{body: stream, headers: headers}
  end

  @doc """
  Builds a form-data `Part` with a text body.
  """
  @spec text_field(binary(), name(), headers()) :: t()
  def text_field(body, name, headers \\ []) do
    headers = maybe_add_content_disposition_header(headers, name)
    binary_body(body, headers)
  end

  @doc """
  Builds a form-data `Part` with a streaming file body.

  Takes the following `Keyword` options in `opts`:

  * `filename`: controls the inclusion of the `filename="foo"` directive in the
    `content-disposition` header. Defaults to `true`, which uses the filename
    from the path on disk. Pass in a `String` to override this, or set to
    `false` to disable this directive.

  * `content_type`: controls the inclusion of the `content-type` header.
    Defaults to `true` which will use `MIME.from_path/1` to detect the mime
    type of the file. Pass in a `String` to override this, or set to `false`
    to disable this header.
  """
  @spec file_field(String.t(), name(), headers(), Keyword.t()) :: t()
  def file_field(path, name, headers \\ [], opts \\ []) do
    filename = Keyword.get(opts, :filename, true)
    content_type = Keyword.get(opts, :content_type, true)

    headers =
      headers
      |> maybe_add_content_type_header(content_type, path)
      |> add_content_disposition_header(name, filename, path)

    file_body(path, headers)
  end

  @doc """
  Builds a form-data `Part` with an in-memory file body.

  Takes the following `Keyword` options in `opts`:

  * `filename`: controls the inclusion of the `filename="foo"` directive in the
    `content-disposition` header. Defaults to `true`, which uses the filename
    from the path on disk. Pass in a `String` to override this, or set to
    `false` to disable this directive.

  * `content_type`: controls the inclusion of the `content-type` header.
    Defaults to `true` which will use `MIME.from_path/1` to detect the mime
    type of the file. Pass in a `String` to override this, or set to `false`
    to disable this header.
  """
  def file_content_field(path, content, name, headers \\ [], opts \\ []) do
    filename = Keyword.get(opts, :filename, true)
    content_type = Keyword.get(opts, :content_type, true)

    headers =
      headers
      |> maybe_add_content_type_header(content_type, path)
      |> add_content_disposition_header(name, filename, path)

    binary_body(content, headers)
  end

  @doc """
  Builds a form-data `Part` with a streaming body.
  """
  @spec stream_field(Enum.t(), name(), headers()) :: t()
  def stream_field(stream, name, headers \\ []) do
    headers = headers |> maybe_add_content_disposition_header(name)
    stream_body(stream, headers)
  end

  defp content_disposition(type, directives) do
    directives
    |> Enum.map(fn {k, v} ->
      "#{k}=\"#{v}\""
    end)
    |> List.insert_at(0, type)
    |> Enum.join("; ")
  end

  defp maybe_add_content_disposition_header(headers, name) do
    unless headers
           |> Enum.map(fn {k, _} -> String.downcase(k) end)
           |> Enum.member?("content-disposition") do
      [{"content-disposition", content_disposition("form-data", name: name)} | headers]
    else
      headers
    end
  end

  defp add_content_disposition_header(headers, name, filename, path) do
    content_disposition_opts = [name: name] |> maybe_add_filename_directive(filename, path)

    header = {"content-disposition", content_disposition("form-data", content_disposition_opts)}

    headers
    |> Enum.concat([header])
  end

  defp maybe_add_content_type_header(headers, true, path) do
    content_type = MIME.from_path(path)

    headers
    |> Enum.concat([{"content-type", content_type}])
  end

  defp maybe_add_content_type_header(headers, content_type, _path) when is_binary(content_type) do
    headers
    |> Enum.concat([{"content-type", content_type}])
  end

  defp maybe_add_content_type_header(headers, false, _path) do
    headers
  end

  defp maybe_add_filename_directive(directives, true, path) do
    directives ++ [filename: Path.basename(path)]
  end

  defp maybe_add_filename_directive(directives, filename, _path) when is_binary(filename) do
    directives ++ [filename: filename]
  end

  defp maybe_add_filename_directive(directives, false, _path) do
    directives
  end
end
