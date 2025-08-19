defprotocol Jido.Eval.Dataset do
  @moduledoc """
  Protocol for pluggable data sources in Jido Eval.

  Defines a common interface for different dataset implementations,
  enabling streaming evaluation of samples from various data sources
  like in-memory lists, JSONL files, CSV files, databases, etc.

  ## Protocol Functions

  - `to_stream/1` - Convert dataset to a stream of samples
  - `sample_type/1` - Get the expected sample type for validation
  - `count/1` - Get the total number of samples for progress tracking

  ## Sample Types

  The protocol supports these sample types:
  - `:single_turn` - For `Jido.Eval.Sample.SingleTurn` samples
  - `:multi_turn` - For `Jido.Eval.Sample.MultiTurn` samples

  ## Examples

      iex> {:ok, dataset} = Jido.Eval.Dataset.InMemory.new([
      ...>   %Jido.Eval.Sample.SingleTurn{user_input: "Hello"}
      ...> ])
      iex> Jido.Eval.Dataset.sample_type(dataset)
      :single_turn
      iex> Jido.Eval.Dataset.count(dataset)
      1

  """

  @doc """
  Convert the dataset to a stream of samples.

  Returns a `Stream` that yields samples one by one, enabling
  memory-efficient processing of large datasets.

  The stream should yield samples of the type indicated by `sample_type/1`.
  """
  @spec to_stream(t()) :: Enumerable.t()
  def to_stream(dataset)

  @doc """
  Get the sample type for this dataset.

  Returns either `:single_turn` or `:multi_turn` to indicate
  what type of samples this dataset contains.
  """
  @spec sample_type(t()) :: :single_turn | :multi_turn
  def sample_type(dataset)

  @doc """
  Get the total number of samples in the dataset.

  Returns the count for progress tracking and batching.
  May return `:unknown` if the count cannot be determined
  without consuming the entire dataset.
  """
  @spec count(t()) :: non_neg_integer() | :unknown
  def count(dataset)
end
