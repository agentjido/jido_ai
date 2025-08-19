defmodule Jido.Eval.Dataset.InMemory do
  @moduledoc """
  In-memory dataset implementation for Jido Eval.

  Stores samples in memory as a list, providing fast access
  and simple dataset creation for testing and small datasets.

  ## Examples

      iex> samples = [
      ...>   %Jido.Eval.Sample.SingleTurn{user_input: "Hello", response: "Hi!"},
      ...>   %Jido.Eval.Sample.SingleTurn{user_input: "Bye", response: "Goodbye!"}
      ...> ]
      iex> {:ok, dataset} = Jido.Eval.Dataset.InMemory.new(samples)
      iex> Jido.Eval.Dataset.count(dataset)
      2

  """
  use TypedStruct

  alias Jido.Eval.Dataset
  alias Jido.Eval.Sample.{SingleTurn, MultiTurn}

  typedstruct do
    @typedoc "An in-memory dataset"

    field(:samples, [SingleTurn.t() | MultiTurn.t()], default: [])
    field(:sample_type, :single_turn | :multi_turn, default: :single_turn)
  end

  @doc """
  Creates a new in-memory dataset from a list of samples.

  Automatically detects the sample type from the first sample.

  ## Examples

      iex> samples = [%Jido.Eval.Sample.SingleTurn{user_input: "Hello"}]
      iex> {:ok, dataset} = Jido.Eval.Dataset.InMemory.new(samples)
      iex> dataset.sample_type
      :single_turn

  """
  @spec new([SingleTurn.t() | MultiTurn.t()]) :: {:ok, t()} | {:error, String.t()}
  def new(samples) when is_list(samples) do
    case detect_sample_type(samples) do
      {:ok, sample_type} ->
        if all_same_type?(samples, sample_type) do
          dataset = %__MODULE__{samples: samples, sample_type: sample_type}
          {:ok, dataset}
        else
          {:error, "All samples must be of the same type"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a new empty in-memory dataset with specified sample type.

  ## Examples

      iex> {:ok, dataset} = Jido.Eval.Dataset.InMemory.empty(:multi_turn)
      iex> dataset.sample_type
      :multi_turn
      iex> Jido.Eval.Dataset.count(dataset)
      0

  """
  @spec empty(:single_turn | :multi_turn) :: {:ok, t()}
  def empty(sample_type) when sample_type in [:single_turn, :multi_turn] do
    dataset = %__MODULE__{samples: [], sample_type: sample_type}
    {:ok, dataset}
  end

  @doc """
  Adds a sample to the dataset.

  The sample must match the dataset's sample type.

  ## Examples

      iex> {:ok, dataset} = Jido.Eval.Dataset.InMemory.empty(:single_turn)
      iex> sample = %Jido.Eval.Sample.SingleTurn{user_input: "Hello"}
      iex> {:ok, updated} = Jido.Eval.Dataset.InMemory.add_sample(dataset, sample)
      iex> Jido.Eval.Dataset.count(updated)
      1

  """
  @spec add_sample(t(), SingleTurn.t() | MultiTurn.t()) :: {:ok, t()} | {:error, String.t()}
  def add_sample(%__MODULE__{} = dataset, sample) do
    if sample_matches_type?(sample, dataset.sample_type) do
      updated_samples = dataset.samples ++ [sample]
      updated_dataset = %{dataset | samples: updated_samples}
      {:ok, updated_dataset}
    else
      {:error, "Sample type does not match dataset type"}
    end
  end

  @doc """
  Gets a sample by index.

  ## Examples

      iex> samples = [%Jido.Eval.Sample.SingleTurn{id: "test", user_input: "Hello"}]
      iex> {:ok, dataset} = Jido.Eval.Dataset.InMemory.new(samples)
      iex> {:ok, sample} = Jido.Eval.Dataset.InMemory.get_sample(dataset, 0)
      iex> sample.id
      "test"

  """
  @spec get_sample(t(), non_neg_integer()) ::
          {:ok, SingleTurn.t() | MultiTurn.t()} | {:error, String.t()}
  def get_sample(%__MODULE__{samples: samples}, index) when is_integer(index) do
    if index >= 0 do
      case Enum.at(samples, index) do
        nil -> {:error, "Index out of bounds"}
        sample -> {:ok, sample}
      end
    else
      {:error, "Index out of bounds"}
    end
  end

  # Protocol implementations

  defimpl Dataset, for: __MODULE__ do
    def to_stream(%Jido.Eval.Dataset.InMemory{samples: samples}) do
      Stream.iterate(0, &(&1 + 1))
      |> Stream.take(length(samples))
      |> Stream.map(&Enum.at(samples, &1))
    end

    def sample_type(%Jido.Eval.Dataset.InMemory{sample_type: sample_type}) do
      sample_type
    end

    def count(%Jido.Eval.Dataset.InMemory{samples: samples}) do
      length(samples)
    end
  end

  # Private helper functions

  defp detect_sample_type([]), do: {:error, "Cannot detect sample type from empty list"}

  defp detect_sample_type([%SingleTurn{} | _]), do: {:ok, :single_turn}
  defp detect_sample_type([%MultiTurn{} | _]), do: {:ok, :multi_turn}
  defp detect_sample_type([sample | _]), do: {:error, "Unknown sample type: #{inspect(sample)}"}

  defp all_same_type?(samples, expected_type) do
    Enum.all?(samples, &sample_matches_type?(&1, expected_type))
  end

  defp sample_matches_type?(%SingleTurn{}, :single_turn), do: true
  defp sample_matches_type?(%MultiTurn{}, :multi_turn), do: true
  defp sample_matches_type?(_, _), do: false
end
