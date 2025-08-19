defmodule Jido.Eval.Dataset.CSV do
  @moduledoc """
  CSV dataset implementation for Jido Eval.

  Reads samples from CSV files with streaming support for
  memory-efficient processing of large datasets.

  The CSV format assumes the first row contains column headers
  that map to sample struct fields. Only supports SingleTurn
  samples due to CSV's flat structure limitations.

  ## Expected CSV Format

  For SingleTurn samples:
  ```csv
  id,user_input,response,reference,retrieved_contexts,reference_contexts,rubrics,tags
  sample_1,"Hello","Hi there!","Hi!","context1;context2","ref1;ref2","accuracy:good","category:greeting"
  ```

  ## Examples

      iex> {:ok, dataset} = Jido.Eval.Dataset.CSV.new("samples.csv")
      iex> Jido.Eval.Dataset.sample_type(dataset)
      :single_turn

  """
  use TypedStruct

  alias Jido.Eval.Dataset
  alias Jido.Eval.Sample.SingleTurn

  # Define custom CSV parser with lenient escape handling
  NimbleCSV.define(JidoCSV,
    separator: ",",
    escape: "\"",
    line_separator: ["\r\n", "\n"],
    moduledoc: false
  )

  typedstruct do
    @typedoc "A CSV dataset"

    field(:file_path, String.t(), default: "")
    field(:headers, [String.t()], default: [])
    field(:separator, String.t(), default: ",")
    field(:encoding, :utf8 | :latin1, default: :utf8)
  end

  @doc """
  Creates a new CSV dataset from a file path.

  ## Options

  - `:separator` - CSV separator (default: `","`)
  - `:encoding` - File encoding (default: `:utf8`)

  ## Examples

      iex> {:ok, dataset} = Jido.Eval.Dataset.CSV.new("data.csv")
      iex> dataset.file_path
      "data.csv"

  """
  @spec new(String.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(file_path, opts \\ []) do
    separator = Keyword.get(opts, :separator, ",")
    encoding = Keyword.get(opts, :encoding, :utf8)

    if File.exists?(file_path) do
      case read_headers(file_path, separator, encoding) do
        {:ok, headers} ->
          dataset = %__MODULE__{
            file_path: file_path,
            headers: headers,
            separator: separator,
            encoding: encoding
          }

          {:ok, dataset}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, "File does not exist: #{file_path}"}
    end
  end

  @doc """
  Writes SingleTurn samples to a CSV file.

  ## Examples

      iex> samples = [%Jido.Eval.Sample.SingleTurn{user_input: "Hello", response: "Hi!"}]
      iex> :ok = Jido.Eval.Dataset.CSV.write("output.csv", samples)

  """
  @spec write(String.t(), [SingleTurn.t()]) :: :ok | {:error, String.t()}
  def write(file_path, samples) when is_list(samples) do
    try do
      if Enum.empty?(samples) do
        {:error, "Cannot write empty sample list"}
      else
        headers = get_standard_headers()
        rows = Enum.map(samples, &sample_to_row(&1, headers))

        csv_data = [headers | rows]
        # Use the standard RFC4180 for writing since it's more reliable
        csv_string = NimbleCSV.RFC4180.dump_to_iodata(csv_data)

        File.write!(file_path, csv_string)
        :ok
      end
    rescue
      e -> {:error, "Failed to write CSV file: #{Exception.message(e)}"}
    end
  end

  # Protocol implementations

  defimpl Dataset, for: __MODULE__ do
    def to_stream(%Jido.Eval.Dataset.CSV{
          file_path: file_path,
          headers: headers,
          encoding: _encoding
        }) do
      # Read entire file and parse with RFC4180 for proper multiline support
      try do
        file_path
        |> File.read!()
        |> NimbleCSV.RFC4180.parse_string(skip_headers: false)
        # Skip header row
        |> Stream.drop(1)
        |> Stream.map(&Jido.Eval.Dataset.CSV.row_to_sample(&1, headers))
        |> Stream.filter(&match?({:ok, _}, &1))
        |> Stream.map(fn {:ok, sample} -> sample end)
      rescue
        NimbleCSV.ParseError ->
          # Fallback to line-by-line parsing for malformed CSVs
          file_path
          |> File.stream!()
          |> Stream.map(&Jido.Eval.Dataset.CSV.manual_parse_csv_line/1)
          # Skip header row
          |> Stream.drop(1)
          |> Stream.map(&Jido.Eval.Dataset.CSV.row_to_sample(&1, headers))
          |> Stream.filter(&match?({:ok, _}, &1))
          |> Stream.map(fn {:ok, sample} -> sample end)
      end
    end

    def sample_type(%Jido.Eval.Dataset.CSV{}) do
      # CSV only supports single-turn samples
      :single_turn
    end

    def count(%Jido.Eval.Dataset.CSV{file_path: file_path}) do
      try do
        file_path
        |> File.stream!()
        |> Enum.count()
        # Subtract header row
        |> Kernel.-(1)
        |> max(0)
      rescue
        _ -> :unknown
      end
    end
  end

  # Private helper functions

  @doc """
  Safely splits a semicolon-separated string, respecting quoted values that may contain semicolons.

  ## Examples

      iex> Jido.Eval.Dataset.CSV.split_list("value1;value2;value3")
      ["value1", "value2", "value3"]
      
      iex> Jido.Eval.Dataset.CSV.split_list("\"value;with;semicolons\";value2")
      ["value;with;semicolons", "value2"]

  """
  @spec split_list(String.t()) :: [String.t()]
  def split_list(value) when is_binary(value) do
    # Use regex to split on semicolons that are not within quoted strings
    # This pattern matches semicolons that are not preceded by an even number of quotes
    ~r/;(?=(?:[^"]*"[^"]*")*[^"]*$)/
    |> Regex.split(value)
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn str ->
      # Remove surrounding quotes if present
      if String.starts_with?(str, "\"") and String.ends_with?(str, "\"") do
        str
        |> String.slice(1..-2//1)
        # Unescape internal quotes
        |> String.replace("\"\"", "\"")
      else
        str
      end
    end)
    |> Enum.reject(&(&1 == ""))
  end

  def split_list(_), do: []

  @doc """
  Checks if a sample map has meaningful data beyond just an ID.
  """
  @spec has_meaningful_data?(map()) :: boolean()
  def has_meaningful_data?(sample_map) when is_map(sample_map) do
    meaningful_fields = [
      :user_input,
      :response,
      :reference,
      :retrieved_contexts,
      :reference_contexts,
      :multi_responses,
      :rubrics,
      :tags
    ]

    Enum.any?(meaningful_fields, fn field ->
      case Map.get(sample_map, field) do
        nil -> false
        "" -> false
        [] -> false
        map when is_map(map) -> map_size(map) > 0
        _ -> true
      end
    end)
  end

  @doc """
  Safely parses CSV stream, falling back to manual parsing for malformed rows.
  """
  @spec parse_csv_stream_safe(Enumerable.t()) :: Enumerable.t()
  def parse_csv_stream_safe(stream) do
    stream
    |> Stream.map(fn line ->
      try do
        # Try to parse with NimbleCSV first
        [parsed_row] = JidoCSV.parse_string(line, skip_headers: false)
        parsed_row
      rescue
        NimbleCSV.ParseError ->
          # Fall back to manual parsing for malformed rows
          manual_parse_csv_line(line)
      end
    end)
  end

  @doc """
  Manual CSV line parser for handling malformed data that NimbleCSV rejects.
  """
  @spec manual_parse_csv_line(String.t()) :: [String.t()]
  def manual_parse_csv_line(line) do
    line
    |> String.trim()
    |> String.split(",")
    |> Enum.map(fn field ->
      field
      |> String.trim()
      |> remove_quotes()
    end)
  end

  defp remove_quotes(field) do
    field = String.trim(field)

    if String.starts_with?(field, "\"") and String.ends_with?(field, "\"") do
      field
      |> String.slice(1..-2//1)
      |> String.replace("\"\"", "\"")
    else
      field
    end
  end

  defp read_headers(file_path, _separator, _encoding) do
    try do
      file_path
      |> File.read!()
      |> NimbleCSV.RFC4180.parse_string(skip_headers: false)
      |> Enum.take(1)
      |> case do
        [headers] -> {:ok, headers}
        [] -> {:error, "Empty CSV file"}
      end
    rescue
      NimbleCSV.ParseError ->
        # Fallback to manual header parsing for malformed CSVs
        try do
          file_path
          |> File.stream!()
          |> Enum.take(1)
          |> case do
            [header_line] ->
              headers = manual_parse_csv_line(header_line)
              {:ok, headers}

            [] ->
              {:error, "Empty CSV file"}
          end
        rescue
          e -> {:error, "Failed to read CSV headers: #{Exception.message(e)}"}
        end

      e ->
        {:error, "Failed to read CSV headers: #{Exception.message(e)}"}
    end
  end

  def row_to_sample(row, headers) do
    try do
      row_map = Enum.zip(headers, row) |> Map.new()
      sample_map = convert_csv_row_to_sample_map(row_map)

      # For CSV data, use lenient sample creation that allows samples
      # without user_input/response if they have other meaningful data
      if has_meaningful_data?(sample_map) do
        sample = struct(SingleTurn, sample_map)
        {:ok, sample}
      else
        {:error, "Sample has no meaningful data"}
      end
    rescue
      e -> {:error, "Failed to convert row to sample: #{Exception.message(e)}"}
    end
  end

  defp convert_csv_row_to_sample_map(row_map) do
    row_map
    |> Map.new(fn {key, value} ->
      atom_key = String.to_atom(key)
      converted_value = convert_csv_value(atom_key, value)
      {atom_key, converted_value}
    end)
    |> Map.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  defp convert_csv_value(key, value)
       when key in [:retrieved_contexts, :reference_contexts, :multi_responses] do
    if value != "" and not is_nil(value) do
      split_list(value)
    else
      nil
    end
  end

  defp convert_csv_value(key, value) when key in [:rubrics, :tags] do
    if value != "" and not is_nil(value) do
      value
      |> split_list()
      |> Enum.reduce(%{}, fn pair, acc ->
        case String.split(pair, ":", parts: 2) do
          [k, v] -> Map.put(acc, k, v)
          [k] -> Map.put(acc, k, "true")
          _ -> acc
        end
      end)
    else
      %{}
    end
  end

  defp convert_csv_value(_key, value) do
    if value == "" or is_nil(value) do
      nil
    else
      value
    end
  end

  defp sample_to_row(%SingleTurn{} = sample, headers) do
    sample_map = SingleTurn.to_map(sample)

    Enum.map(headers, fn header ->
      atom_key = String.to_atom(header)
      value = Map.get(sample_map, atom_key)
      convert_sample_value_to_csv(atom_key, value)
    end)
  end

  defp convert_sample_value_to_csv(key, value)
       when key in [:retrieved_contexts, :reference_contexts, :multi_responses] do
    case value do
      list when is_list(list) -> Enum.join(list, ";")
      _ -> ""
    end
  end

  defp convert_sample_value_to_csv(key, value) when key in [:rubrics, :tags] do
    case value do
      map when is_map(map) ->
        map
        |> Enum.map(fn {k, v} -> "#{k}:#{v}" end)
        |> Enum.join(";")

      _ ->
        ""
    end
  end

  defp convert_sample_value_to_csv(_key, value) do
    case value do
      nil -> ""
      val -> to_string(val)
    end
  end

  defp get_standard_headers do
    [
      "id",
      "user_input",
      "retrieved_contexts",
      "reference_contexts",
      "response",
      "multi_responses",
      "reference",
      "rubrics",
      "tags"
    ]
  end
end
