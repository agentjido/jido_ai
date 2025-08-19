defmodule Jido.Eval.Dataset.JSONL do
  @moduledoc """
  JSONL (JSON Lines) dataset implementation for Jido Eval.

  Reads samples from JSONL files with streaming support for
  memory-efficient processing of large datasets.

  Each line in the JSONL file should be a valid JSON object
  representing a sample. The sample type is detected from
  the structure of the JSON objects.

  ## Examples

      iex> {:ok, dataset} = Jido.Eval.Dataset.JSONL.new("samples.jsonl", :single_turn)
      iex> Jido.Eval.Dataset.sample_type(dataset)
      :single_turn

  """
  use TypedStruct

  alias Jido.Eval.Dataset
  alias Jido.Eval.Sample.{SingleTurn, MultiTurn}

  typedstruct do
    @typedoc "A JSONL dataset"

    field(:file_path, String.t(), default: "")
    field(:sample_type, :single_turn | :multi_turn, default: :single_turn)
    field(:encoding, :utf8 | :latin1, default: :utf8)
  end

  @doc """
  Creates a new JSONL dataset from a file path.

  ## Options

  - `:encoding` - File encoding (default: `:utf8`)

  ## Examples

      iex> {:ok, dataset} = Jido.Eval.Dataset.JSONL.new("data.jsonl", :single_turn)
      iex> dataset.file_path
      "data.jsonl"

  """
  @spec new(String.t(), :single_turn | :multi_turn, keyword()) ::
          {:ok, t()} | {:error, String.t()}
  def new(file_path, sample_type, opts \\ []) do
    encoding = Keyword.get(opts, :encoding, :utf8)

    if File.exists?(file_path) do
      dataset = %__MODULE__{
        file_path: file_path,
        sample_type: sample_type,
        encoding: encoding
      }

      {:ok, dataset}
    else
      {:error, "File does not exist: #{file_path}"}
    end
  end

  @doc """
  Creates a JSONL dataset from an existing file, auto-detecting sample type.

  Reads the first valid line to determine the sample type.

  ## Examples

      iex> {:ok, dataset} = Jido.Eval.Dataset.JSONL.auto_detect("data.jsonl")
      iex> Jido.Eval.Dataset.sample_type(dataset)
      :single_turn

  """
  @spec auto_detect(String.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def auto_detect(file_path, opts \\ []) do
    if File.exists?(file_path) do
      case detect_sample_type_from_file(file_path) do
        {:ok, sample_type} ->
          new(file_path, sample_type, opts)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, "File does not exist: #{file_path}"}
    end
  end

  @doc """
  Writes samples to a JSONL file.

  ## Examples

      iex> samples = [%Jido.Eval.Sample.SingleTurn{user_input: "Hello"}]
      iex> :ok = Jido.Eval.Dataset.JSONL.write("output.jsonl", samples)

  """
  @spec write(String.t(), [SingleTurn.t() | MultiTurn.t()]) :: :ok | {:error, String.t()}
  def write(file_path, samples) when is_list(samples) do
    try do
      file = File.open!(file_path, [:write])

      samples
      |> Stream.map(&sample_to_json_line/1)
      |> Enum.each(&IO.write(file, &1))

      File.close(file)
      :ok
    rescue
      e -> {:error, "Failed to write file: #{Exception.message(e)}"}
    end
  end

  # Protocol implementations

  defimpl Dataset, for: __MODULE__ do
    def to_stream(%Jido.Eval.Dataset.JSONL{
          file_path: file_path,
          sample_type: sample_type,
          encoding: _encoding
        }) do
      file_path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Stream.map(&Jido.Eval.Dataset.JSONL.parse_json_line(&1, sample_type))
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Stream.map(fn {:ok, sample} -> sample end)
    end

    def sample_type(%Jido.Eval.Dataset.JSONL{sample_type: sample_type}) do
      sample_type
    end

    def count(%Jido.Eval.Dataset.JSONL{file_path: file_path}) do
      try do
        file_path
        |> File.stream!()
        |> Stream.map(&String.trim/1)
        |> Stream.reject(&(&1 == ""))
        |> Enum.count()
      rescue
        _ -> :unknown
      end
    end
  end

  # Private helper functions

  defp detect_sample_type_from_file(file_path) do
    try do
      file_path
      |> File.stream!()
      |> Stream.take(10)
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Stream.map(&Jason.decode/1)
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Stream.map(fn {:ok, data} -> data end)
      |> Enum.take(1)
      |> case do
        [first_sample] -> detect_sample_type_from_map(first_sample)
        [] -> {:error, "No valid JSON found in file"}
      end
    rescue
      e -> {:error, "Failed to read file: #{Exception.message(e)}"}
    end
  end

  defp detect_sample_type_from_map(map) when is_map(map) do
    cond do
      Map.has_key?(map, "conversation") or Map.has_key?(map, :conversation) ->
        {:ok, :multi_turn}

      Map.has_key?(map, "user_input") or Map.has_key?(map, :user_input) or
        Map.has_key?(map, "response") or Map.has_key?(map, :response) ->
        {:ok, :single_turn}

      true ->
        {:error, "Cannot determine sample type from JSON structure"}
    end
  end

  def parse_json_line(line, sample_type) do
    with {:ok, data} <- Jason.decode(line),
         {:ok, sample} <- create_sample_from_map(data, sample_type) do
      {:ok, sample}
    else
      {:error, %Jason.DecodeError{}} -> {:error, "Invalid JSON"}
      {:error, reason} -> {:error, "Failed to parse line: #{inspect(reason)}"}
    end
  end

  defp create_sample_from_map(map, :single_turn), do: SingleTurn.from_map(map)
  defp create_sample_from_map(map, :multi_turn), do: MultiTurn.from_map(map)

  defp sample_to_json_line(sample) do
    map =
      case sample do
        %SingleTurn{} -> SingleTurn.to_map(sample)
        %MultiTurn{} -> MultiTurn.to_map(sample)
      end

    case Jason.encode(map) do
      {:ok, json} -> json <> "\n"
      {:error, _} -> ""
    end
  end
end
