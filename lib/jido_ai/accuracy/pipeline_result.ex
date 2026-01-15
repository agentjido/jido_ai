defmodule Jido.AI.Accuracy.PipelineResult do
  @moduledoc """
  Result of a pipeline execution with trace and metadata.

  A PipelineResult contains the final answer from the accuracy pipeline
  along with comprehensive trace information and metadata about the execution.

  ## Fields

  - `:answer` - The final answer string, or nil if abstained
  - `:confidence` - Confidence score in the answer [0.0, 1.0]
  - `:action` - The routing action taken (:direct, :with_verification, etc.)
  - `:trace` - List of trace entries for each executed stage
  - `:metadata` - Execution metadata (timing, token counts, etc.)

  ## Trace Entries

  Each trace entry contains:
  - `:stage` - Name of the stage
  - `:status` - :ok, :skipped, or :error
  - `:duration_ms` - Execution time in milliseconds
  - `:result` - Stage result data or error reason

  ## Usage

      # Check if pipeline succeeded
      if PipelineResult.success?(result) do
        IO.puts("Answer: " <> result.answer)
      end

      # Get execution time
      total_time = PipelineResult.total_duration_ms(result)

      # Get stage trace
      calibration_trace = PipelineResult.stage_trace(result, :calibration)

  """

  alias Jido.AI.Accuracy.{DifficultyEstimate, RoutingResult}

  @type t :: %__MODULE__{
          answer: String.t() | nil,
          confidence: float(),
          action: RoutingResult.action(),
          trace: [trace_entry()],
          metadata: metadata()
        }

  @type trace_entry :: %{
          stage: atom(),
          status: :ok | :skipped | :error,
          duration_ms: non_neg_integer(),
          result: map() | nil,
          error: atom() | nil
        }

  @type metadata :: %{
          optional(:total_duration_ms) => non_neg_integer(),
          optional(:total_tokens) => non_neg_integer(),
          optional(:num_candidates) => non_neg_integer(),
          optional(:difficulty) => DifficultyEstimate.t(),
          optional(atom()) => term()
        }

  @enforce_keys [:confidence, :action]
  defstruct [
    :answer,
    :confidence,
    :action,
    trace: [],
    metadata: %{}
  ]

  @doc """
  Creates a new PipelineResult from the given attributes.

  ## Parameters

  - `attrs` - Map with result attributes:
    - `:answer` - Final answer string (optional, defaults to nil)
    - `:confidence` - Confidence score [0-1]
    - `:action` - Routing action taken
    - `:trace` - List of trace entries (optional)
    - `:metadata` - Additional metadata (optional)

  ## Returns

  `{:ok, result}` on success, `{:error, reason}` on validation failure.

  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    confidence = Map.get(attrs, :confidence, 0.5)
    action = Map.get(attrs, :action, :direct)

    with :ok <- validate_confidence(confidence),
         :ok <- validate_action(action) do
      result = %__MODULE__{
        answer: Map.get(attrs, :answer),
        confidence: confidence,
        action: action,
        trace: Map.get(attrs, :trace, []),
        metadata: Map.get(attrs, :metadata, %{})
      }

      {:ok, result}
    end
  end

  @doc """
  Creates a new PipelineResult, raising on error.

  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "Invalid PipelineResult: #{format_error(reason)}"
    end
  end

  @doc """
  Returns true if the pipeline execution was successful.

  A successful execution has:
  - No errors in required stages
  - A non-nil answer (unless abstained)

  """
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{action: :abstain}), do: true
  def success?(%__MODULE__{answer: nil}), do: false
  def success?(%__MODULE__{}), do: true

  @doc """
  Returns true if the pipeline abstained from answering.

  """
  @spec abstained?(t()) :: boolean()
  def abstained?(%__MODULE__{action: :abstain}), do: true
  def abstained?(%__MODULE__{}), do: false

  @doc """
  Returns true if the answer was returned directly (high confidence).

  """
  @spec direct?(t()) :: boolean()
  def direct?(%__MODULE__{action: :direct}), do: true
  def direct?(%__MODULE__{}), do: false

  @doc """
  Calculates the total execution time from trace entries.

  """
  @spec total_duration_ms(t()) :: non_neg_integer()
  def total_duration_ms(%__MODULE__{trace: trace}) do
    trace
    |> Enum.map(fn
      %{duration_ms: ms} when is_integer(ms) -> ms
      _ -> 0
    end)
    |> Enum.sum()
  end

  @doc """
  Gets the trace entry for a specific stage.

  Returns nil if the stage was not executed.

  """
  @spec stage_trace(t(), atom()) :: trace_entry() | nil
  def stage_trace(%__MODULE__{trace: trace}, stage_name) when is_atom(stage_name) do
    Enum.find(trace, fn
      %{stage: ^stage_name} -> true
      _ -> false
    end)
  end

  @doc """
  Gets all trace entries that had errors.

  """
  @spec error_traces(t()) :: [trace_entry()]
  def error_traces(%__MODULE__{trace: trace}) do
    Enum.filter(trace, fn
      %{status: :error} -> true
      _ -> false
    end)
  end

  @doc """
  Adds a trace entry to the result.

  """
  @spec add_trace(t(), trace_entry()) :: t()
  def add_trace(%__MODULE__{trace: trace} = result, entry) when is_map(entry) do
    %{result | trace: trace ++ [entry]}
  end

  @doc """
  Updates the metadata with new values.

  """
  @spec put_metadata(t(), atom(), term()) :: t()
  def put_metadata(%__MODULE__{metadata: metadata} = result, key, value) when is_atom(key) do
    %{result | metadata: Map.put(metadata, key, value)}
  end

  @doc """
  Merges a map of metadata into the result.

  """
  @spec merge_metadata(t(), map()) :: t()
  def merge_metadata(%__MODULE__{metadata: metadata} = result, new_metadata) when is_map(new_metadata) do
    %{result | metadata: Map.merge(metadata, new_metadata)}
  end

  @doc """
  Creates a trace entry for a stage execution.

  """
  @spec trace_entry(atom(), :ok | :skipped | :error, non_neg_integer(), map() | term()) :: trace_entry()
  def trace_entry(stage, status, duration_ms, result)

  def trace_entry(stage, :ok, duration_ms, stage_result) when is_map(stage_result) do
    %{
      stage: stage,
      status: :ok,
      duration_ms: duration_ms,
      result: stage_result,
      error: nil
    }
  end

  def trace_entry(stage, :error, duration_ms, error_reason) do
    %{
      stage: stage,
      status: :error,
      duration_ms: duration_ms,
      result: nil,
      error: error_reason
    }
  end

  def trace_entry(stage, :skipped, _duration_ms, _reason) do
    %{
      stage: stage,
      status: :skipped,
      duration_ms: 0,
      result: nil,
      error: nil
    }
  end

  @doc """
  Converts the result to a map for serialization.

  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    result
    |> Map.from_struct()
    |> Map.put(:success?, success?(result))
    |> Map.put(:abstained?, abstained?(result))
    |> Map.put(:total_duration_ms, total_duration_ms(result))
  end

  # Private functions

  defp validate_confidence(conf) when is_number(conf) and conf >= 0.0 and conf <= 1.0, do: :ok
  defp validate_confidence(_), do: {:error, :invalid_confidence}

  defp validate_action(action)
       when action in [:direct, :with_verification, :with_citations, :abstain, :escalate],
       do: :ok

  defp validate_action(_), do: {:error, :invalid_action}

  defp format_error(atom) when is_atom(atom), do: atom
  defp format_error(_), do: :invalid_attributes
end
