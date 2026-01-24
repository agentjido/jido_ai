defmodule Jido.AI.Accuracy.PipelineStage do
  @moduledoc """
  Behavior for pipeline stages in the accuracy improvement pipeline.

  Each stage receives the accumulated pipeline state and returns
  an updated state with its results. Stages are executed sequentially
  by the Pipeline orchestrator.

  ## Stage Behavior

  A stage must implement the `execute/2` callback which receives:
  - `input` - The accumulated state from previous stages
  - `config` - Configuration specific to this stage

  The callback should return:
  - `{:ok, updated_state, metadata}` - Success with updated state and metadata
  - `{:error, reason}` - Failure with reason

  ## Required vs Optional Stages

  Required stages must succeed for the pipeline to continue.
  Optional stages can fail without stopping the pipeline (their results
  will be marked as errors in the trace).

  ## Implementing a Stage

      defmodule MyStage do
        @behaviour Jido.AI.Accuracy.PipelineStage

        @impl PipelineStage
        def name, do: :my_stage

        @impl PipelineStage
        def required?, do: true

        @impl PipelineStage
        def execute(input, config) do
          # Process input with config
          {:ok, updated_state, %{duration_ms: 10}}
        end
      end

  ## Metadata

  The metadata returned from `execute/2` should include:
  - `:duration_ms` - Execution time in milliseconds
  - Stage-specific metrics and information

  """

  @type stage_result :: {:ok, map(), metadata()} | {:error, term()}

  @type metadata :: %{
          optional(:duration_ms) => non_neg_integer(),
          optional(atom()) => term()
        }

  @doc """
  Returns the name of this stage as an atom.

  The name is used for:
  - Trace identification
  - Telemetry event names
  - Configuration lookup

  """
  @callback name() :: atom()

  @doc """
  Executes the stage logic.

  Receives the accumulated state from previous stages and
  stage-specific configuration. Returns an updated state
  with the stage's results.

  ## Parameters

  - `input` - Map containing accumulated state from previous stages
  - `config` - Map with stage-specific configuration

  ## Returns

  - `{:ok, updated_state, metadata}` - Success with updated state
  - `{:error, reason}` - Failure with reason atom

  """
  @callback execute(input :: map(), config :: map()) :: stage_result()

  @doc """
  Returns whether this stage is required for pipeline execution.

  Required stages must succeed for the pipeline to continue.
  Optional stages can fail without stopping the pipeline.

  Default implementation returns `true` (stage is required).

  """
  @callback required?() :: boolean()

  @optional_callbacks [required?: 0]

  @doc """
  Checks if the given module is a pipeline stage.

  A module is considered a pipeline stage if it implements the
  PipelineStage behavior (has the name/0 and execute/2 callbacks).

  """
  @spec pipeline_stage?(module()) :: boolean()
  def pipeline_stage?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :name, 0) and
      function_exported?(module, :execute, 2)
  end

  def pipeline_stage?(_), do: false

  @doc """
  Executes a stage with timeout protection.

  Wraps the stage's execute/2 call with a timeout to prevent
  indefinite blocking. Returns timeout error if exceeded.

  """
  @spec execute_with_timeout(module(), map(), map(), pos_integer()) :: stage_result()
  def execute_with_timeout(stage_module, input, config, timeout \\ 30_000) do
    start_time = System.monotonic_time(:millisecond)

    task =
      Task.async(fn ->
        stage_module.execute(input, config)
      end)

    case Task.yield(task, timeout) do
      {:ok, {:ok, state, stage_metadata}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        metadata = Map.put(stage_metadata, :duration_ms, duration)
        {:ok, state, metadata}

      {:ok, {:error, reason}} ->
        {:error, reason}

      {:exit, _reason} ->
        {:error, :stage_crashed}

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end
end
