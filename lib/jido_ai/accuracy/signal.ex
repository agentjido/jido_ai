defmodule Jido.AI.Accuracy.Signal do
  @moduledoc """
  Signals for accuracy pipeline operations.

  These signals are emitted during accuracy pipeline execution and can be
  handled by agents or other components.

  ## Signal Types

  - `Jido.AI.Accuracy.Signal.Result` - Pipeline completion with answer and metadata
  - `Jido.AI.Accuracy.Signal.Error` - Pipeline execution error

  ## Usage

  Agents can handle these signals via `signal_routes/1`:

      def signal_routes(_agent) do
        %{
          "accuracy.result" => :handle_accuracy_result,
          "accuracy.error" => :handle_accuracy_error
        }
      end

  ## Signal Data

  ### Result Signal

  - `:call_id` - Correlation ID for the pipeline call
  - `:query` - The query that was processed
  - `:preset` - The preset used (if applicable)
  - `:answer` - The final answer
  - `:confidence` - Final confidence score
  - `:candidates` - Number of candidates generated
  - `:trace` - Execution trace with stage results
  - `:duration_ms` - Execution duration in milliseconds
  - `:metadata` - Additional metadata (tokens, verification scores, etc.)

  ### Error Signal

  - `:call_id` - Correlation ID for the pipeline call
  - `:query` - The query that failed
  - `:preset` - The preset used (if applicable)
  - `:error` - Error reason or exception
  - `:stage` - Stage where error occurred (if applicable)
  """

  defmodule Result do
    @moduledoc """
    Signal emitted when the accuracy pipeline completes successfully.

    ## Fields

    - `:call_id` (required) - Correlation ID for the pipeline call
    - `:query` (required) - The query that was processed
    - `:preset` (optional) - The preset used
    - `:answer` (optional) - The final answer
    - `:confidence` (optional) - Final confidence score (0.0-1.0)
    - `:candidates` (optional) - Number of candidates generated
    - `:trace` (optional) - Execution trace with stage results
    - `:duration_ms` (optional) - Execution duration in milliseconds
    - `:metadata` (optional) - Additional metadata

    ## Metadata Contents

    The metadata map may contain:
    - `:input_tokens` - Total input tokens used
    - `:output_tokens` - Total output tokens used
    - `:total_tokens` - Sum of input and output tokens
    - `:verification_score` - Verification score (if verified)
    - `:calibration_action` - Action taken by calibration gate
    - `:calibration_level` - Confidence level (high/medium/low)
    """

    use Jido.Signal,
      type: "accuracy.result",
      default_source: "/accuracy/pipeline",
      schema: [
        call_id: [
          type: :string,
          required: true,
          doc: "Correlation ID for the pipeline call"
        ],
        query: [
          type: :string,
          required: true,
          doc: "The query that was processed"
        ],
        preset: [
          type: :atom,
          required: false,
          doc: "The preset used (:fast, :balanced, :accurate, :coding, :research)"
        ],
        answer: [
          type: :string,
          required: false,
          doc: "The final answer"
        ],
        confidence: [
          type: :float,
          required: false,
          doc: "Final confidence score (0.0-1.0)"
        ],
        candidates: [
          type: :integer,
          required: false,
          doc: "Number of candidates generated"
        ],
        trace: [
          type: :map,
          required: false,
          doc: "Execution trace with stage results"
        ],
        duration_ms: [
          type: :integer,
          required: false,
          doc: "Execution duration in milliseconds"
        ],
        metadata: [
          type: :map,
          required: false,
          doc: "Additional metadata (tokens, verification, calibration)"
        ]
      ]

    @doc """
    Creates a Result signal from a PipelineResult.
    """
    def from_pipeline_result(call_id, query, preset, result, start_time \\ nil)

    def from_pipeline_result(call_id, query, preset, {:ok, result}, start_time)
        when is_binary(call_id) and is_binary(query) do
      duration_ms =
        if start_time do
          System.monotonic_time(:millisecond) - start_time
        end

      # Build base signal data with required fields
      base_attrs = %{
        call_id: call_id,
        query: query,
        preset: preset,
        answer: Map.get(result, :answer),
        confidence: Map.get(result, :confidence),
        candidates: get_in(result, [:metadata, :num_candidates]),
        trace: Map.get(result, :trace),
        duration_ms: duration_ms,
        metadata: build_metadata(result)
      }

      # Filter out nil values for type validation
      attrs =
        base_attrs
        |> Enum.filter(fn {_k, v} -> v != nil end)
        |> Map.new()

      new!(attrs)
    end

    def from_pipeline_result(call_id, query, preset, {:error, reason}, _start_time) do
      # Reference the Error module from the parent module
      # Result is nested inside Jido.AI.Accuracy.Signal, so Error is a sibling
      {:ok, signal} =
        Jido.AI.Accuracy.Signal.Error.new(%{
          call_id: call_id,
          query: query,
          preset: preset,
          error: reason
        })

      signal
    end

    defp build_metadata(result) do
      input_tokens = get_in(result, [:metadata, :input_tokens])
      output_tokens = get_in(result, [:metadata, :output_tokens])

      %{}
      |> maybe_put(:num_candidates, get_in(result, [:metadata, :num_candidates]))
      |> maybe_put(:input_tokens, input_tokens)
      |> maybe_put(:output_tokens, output_tokens)
      |> maybe_put(
        :total_tokens,
        get_in(result, [:metadata, :total_tokens]) || compute_total_tokens(input_tokens, output_tokens)
      )
      |> maybe_put(:verification_score, get_in(result, [:metadata, :verification_score]))
      |> maybe_put(:calibration_action, get_in(result, [:metadata, :calibration_action]))
      |> maybe_put(:calibration_level, get_in(result, [:metadata, :calibration_level]))
    end

    defp compute_total_tokens(input, output) when is_integer(input) and is_integer(output) do
      input + output
    end

    defp compute_total_tokens(_, _), do: nil

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, key, value), do: Map.put(map, key, value)
  end

  defmodule Error do
    @moduledoc """
    Signal emitted when the accuracy pipeline fails.

    ## Fields

    - `:call_id` (required) - Correlation ID for the pipeline call
    - `:query` (required) - The query that failed
    - `:preset` (optional) - The preset being used
    - `:error` (required) - Error reason or exception
    - `:stage` (optional) - Stage where error occurred
    - `:message` (optional) - Human-readable error message
    """

    use Jido.Signal,
      type: "accuracy.error",
      default_source: "/accuracy/pipeline",
      schema: [
        call_id: [
          type: :string,
          required: true,
          doc: "Correlation ID for the pipeline call"
        ],
        query: [
          type: :string,
          required: true,
          doc: "The query that failed"
        ],
        preset: [
          type: :atom,
          required: false,
          doc: "The preset being used"
        ],
        error: [
          type: :any,
          required: true,
          doc: "Error reason or exception"
        ],
        stage: [
          type: :atom,
          required: false,
          doc: "Stage where error occurred"
        ],
        message: [
          type: :string,
          required: false,
          doc: "Human-readable error message"
        ]
      ]

    @doc """
    Creates an Error signal from an exception or error reason.
    """
    def from_exception(call_id, query, preset, exception, stage \\ nil)

    def from_exception(call_id, query, preset, {%{__exception__: true} = exception, _stack}, stage) do
      message = Exception.message(exception)

      base_attrs = %{
        call_id: call_id,
        query: query,
        preset: preset,
        error: message,
        stage: stage,
        message: message
      }

      # Filter out nil values for type validation
      attrs =
        base_attrs
        |> Enum.filter(fn {_k, v} -> v != nil end)
        |> Map.new()

      new!(attrs)
    end

    def from_exception(call_id, query, preset, reason, stage) do
      message =
        cond do
          is_binary(reason) -> reason
          is_atom(reason) -> inspect(reason)
          true -> inspect(reason, limit: 500)
        end

      base_attrs = %{
        call_id: call_id,
        query: query,
        preset: preset,
        error: reason,
        stage: stage,
        message: message
      }

      # Filter out nil values for type validation
      attrs =
        base_attrs
        |> Enum.filter(fn {_k, v} -> v != nil end)
        |> Map.new()

      new!(attrs)
    end
  end
end
