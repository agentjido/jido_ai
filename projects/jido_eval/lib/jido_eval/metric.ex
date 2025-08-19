defmodule Jido.Eval.Metric do
  @moduledoc """
  Behaviour for evaluation metrics in Jido Eval.

  Metrics are pluggable components that measure different aspects of AI system performance.
  Each metric evaluates samples and returns numeric scores with optional metadata.

  ## Metric Metadata

  Metrics must provide metadata describing their capabilities:

  - `name/0` - Human-readable metric name
  - `description/0` - Brief description of what the metric measures
  - `required_fields/0` - List of required sample fields
  - `sample_types/0` - List of supported sample types (`:single_turn`, `:multi_turn`)
  - `score_range/0` - Tuple of `{min, max}` score values

  ## Examples

      defmodule MyMetric do
        @behaviour Jido.Eval.Metric

        @impl true
        def name, do: "Custom Metric"

        @impl true 
        def description, do: "Measures custom aspect of responses"

        @impl true
        def required_fields, do: [:response, :user_input]

        @impl true
        def sample_types, do: [:single_turn]

        @impl true
        def score_range, do: {0.0, 1.0}

        @impl true
        def evaluate(sample, config, opts) do
          # Implementation here
          {:ok, 0.85}
        end
      end

  ## Registration

  Metrics are registered with the ComponentRegistry:

      Jido.Eval.ComponentRegistry.register(:metric, MyMetric)

  ## Error Handling

  Metrics should return `{:ok, score}` for successful evaluation or 
  `{:error, reason}` for failures. Common error patterns:

  - `{:error, {:missing_field, field}}` - Required field not present
  - `{:error, {:invalid_sample_type, type}}` - Unsupported sample type
  - `{:error, {:llm_error, reason}}` - LLM generation failed
  - `{:error, {:timeout, duration}}` - Evaluation timed out
  """

  @type sample :: Jido.Eval.Sample.SingleTurn.t() | Jido.Eval.Sample.MultiTurn.t()
  @type config :: Jido.Eval.Config.t()
  @type opts :: keyword()
  @type score :: float()
  @type error_reason ::
          {:missing_field, atom()}
          | {:invalid_sample_type, atom()}
          | {:llm_error, term()}
          | {:timeout, integer()}
          | term()

  @doc """
  Human-readable name of the metric.

  ## Examples

      iex> Jido.Eval.Metrics.Faithfulness.name()
      "Faithfulness"
  """
  @callback name() :: String.t()

  @doc """
  Brief description of what the metric measures.

  ## Examples

      iex> String.contains?(Jido.Eval.Metrics.Faithfulness.description(), "grounded")
      true
  """
  @callback description() :: String.t()

  @doc """
  List of required fields that must be present in the sample.

  ## Examples

      iex> Jido.Eval.Metrics.Faithfulness.required_fields()
      [:response, :retrieved_contexts]
  """
  @callback required_fields() :: [atom()]

  @doc """
  List of sample types this metric supports.

  ## Examples

      iex> Jido.Eval.Metrics.Faithfulness.sample_types()
      [:single_turn]
  """
  @callback sample_types() :: [:single_turn | :multi_turn]

  @doc """
  Score range as `{min, max}` tuple.

  ## Examples

      iex> Jido.Eval.Metrics.Faithfulness.score_range()
      {0.0, 1.0}
  """
  @callback score_range() :: {number(), number()}

  @doc """
  Evaluate a sample and return a numeric score.

  ## Parameters

  - `sample` - Sample to evaluate (SingleTurn or MultiTurn)
  - `config` - Evaluation configuration
  - `opts` - Additional options (timeout, model overrides, etc.)

  ## Returns

  - `{:ok, score}` - Successful evaluation with numeric score
  - `{:error, reason}` - Evaluation failed

  ## Examples

      {:ok, 0.85} = MyMetric.evaluate(sample, config, [])
      {:error, {:missing_field, :response}} = MyMetric.evaluate(incomplete_sample, config, [])
  """
  @callback evaluate(sample(), config(), opts()) :: {:ok, score()} | {:error, error_reason()}

  @doc """
  Validate that a sample has all required fields for this metric.

  ## Parameters

  - `sample` - Sample to validate
  - `metric` - Metric module

  ## Returns

  - `:ok` - Sample is valid
  - `{:error, reason}` - Validation failed

  ## Examples

      :ok = Jido.Eval.Metric.validate_sample(sample, MyMetric)
      {:error, {:missing_field, :response}} = Jido.Eval.Metric.validate_sample(incomplete_sample, MyMetric)
  """
  @spec validate_sample(sample(), module()) :: :ok | {:error, error_reason()}
  def validate_sample(sample, metric) do
    sample_type = get_sample_type(sample)

    if sample_type not in metric.sample_types() do
      {:error, {:invalid_sample_type, sample_type}}
    else
      validate_required_fields(sample, metric.required_fields())
    end
  end

  @doc """
  Get the type of a sample.

  ## Parameters

  - `sample` - Sample to inspect

  ## Returns

  - `:single_turn` - SingleTurn sample
  - `:multi_turn` - MultiTurn sample

  ## Examples

      :single_turn = Jido.Eval.Metric.get_sample_type(%SingleTurn{})
      :multi_turn = Jido.Eval.Metric.get_sample_type(%MultiTurn{})
  """
  @spec get_sample_type(sample()) :: :single_turn | :multi_turn
  def get_sample_type(%Jido.Eval.Sample.SingleTurn{}), do: :single_turn
  def get_sample_type(%Jido.Eval.Sample.MultiTurn{}), do: :multi_turn

  # Private helper functions

  defp validate_required_fields(sample, required_fields) do
    missing_fields =
      required_fields
      |> Enum.filter(fn field ->
        case Map.get(sample, field) do
          nil -> true
          "" -> true
          [] -> true
          _ -> false
        end
      end)

    case missing_fields do
      [] -> :ok
      [field | _] -> {:error, {:missing_field, field}}
    end
  end
end
