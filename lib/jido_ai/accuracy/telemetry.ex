defmodule Jido.AI.Accuracy.Telemetry do
  @moduledoc """
  Telemetry for accuracy pipeline operations.

  This module provides telemetry emission for the accuracy pipeline,
  enabling observability, monitoring, and debugging.

  ## Events

  The following telemetry events are emitted:

  ### Pipeline Events

  | Event | Measurements | Metadata |
  |-------|--------------|----------|
  | `[:jido, :accuracy, :pipeline, :start]` | `%{system_time: integer()}` | `query, preset, config` |
  | `[:jido, :accuracy, :pipeline, :stop]` | `%{duration: integer()}` | `query, preset, config, result` |
  | `[:jido, :accuracy, :pipeline, :exception]` | `%{duration: integer()}` | `query, preset, kind, reason, stacktrace` |

  ### Stage Events

  | Event | Measurements | Metadata |
  |-------|--------------|----------|
  | `[:jido, :accuracy, :stage, :start]` | `%{system_time: integer()}` | `stage_name, query, stage_config` |
  | `[:jido, :accuracy, :stage, :stop]` | `%{duration: integer()}` | `stage_name, query, stage_metadata` |
  | `[:jido, :accuracy, :stage, :exception]` | `%{duration: integer()}` | `stage_name, kind, reason` |

  ## Usage

  ### Direct Event Emission

      # Start pipeline
      Telemetry.emit_pipeline_start("What is 2+2?", config)

      # Execute pipeline...
      result = Pipeline.run(pipeline, query, opts)

      # Stop pipeline
      Telemetry.emit_pipeline_stop(start_time, query, result)

  ### Using Spans

  The recommended way to track pipeline and stage execution is using spans:

      # Pipeline span
      {result, metadata} = Telemetry.pipeline_span(query, config, fn ->
        # Pipeline execution here
        {:ok, result} = Pipeline.run(pipeline, query, opts)
        result
      end)

      # Stage span
      {result, metadata} = Telemetry.stage_span(:generation, query, fn ->
        # Stage execution here
        GenerationStage.execute(input, config)
      end)

  ## Attaching Handlers

  To handle telemetry events, use `:telemetry.attach/4`:

      # In your application code
      :telemetry.attach(
        "my-handler",
        [:jido, :accuracy, :pipeline, :stop],
        &handle_pipeline_stop/4,
        nil
      )

      # The handler function would be defined as:
      # defp handle_pipeline_stop(_event, measurements, metadata, _config) do
      #   Logger.debug("Pipeline completed in \#{measurements.duration}ns")
      # end

  ## Measurements

  - `:duration` - Monotonic time in nanoseconds (for stop/exception events)
  - `:system_time` - System time in native units (for start events)

  ## Metadata

  Metadata includes context about the event:
  - `:query` - The query being processed
  - `:preset` - The preset used (if applicable)
  - `:stage_name` - The name of the stage (for stage events)
  - `:config` - Pipeline/stage configuration
  - `:result` - The pipeline result (for stop events)
  - `:kind` - Exception kind (for exception events)
  - `:reason` - Exception reason (for exception events)
  - `:stacktrace` - Exception stacktrace (for exception events)

  ## Token Usage

  Token usage is extracted from result metadata when available:
  - `:input_tokens` - Total input tokens
  - `:output_tokens` - Total output tokens
  - `:total_tokens` - Sum of input and output tokens

  ## Quality Metrics

  Quality metrics are extracted from result metadata when available:
  - `:confidence` - Final confidence score
  - `:verification_score` - Verification score (if verified)
  - `:num_candidates` - Number of candidates generated
  """

  # Event name constants
  @pipeline_start_event [:jido, :accuracy, :pipeline, :start]
  @pipeline_stop_event [:jido, :accuracy, :pipeline, :stop]
  @pipeline_exception_event [:jido, :accuracy, :pipeline, :exception]
  @stage_start_event [:jido, :accuracy, :stage, :start]
  @stage_stop_event [:jido, :accuracy, :stage, :stop]
  @stage_exception_event [:jido, :accuracy, :stage, :exception]

  # Event prefixes for :telemetry.span/3 (without :start/:stop suffix)
  @pipeline_event_prefix [:jido, :accuracy, :pipeline]
  @stage_event_prefix [:jido, :accuracy, :stage]

  # Public API

  @doc """
  Emits a pipeline start event.

  ## Parameters

  - `query` - The query being processed
  - `config` - The pipeline configuration (optional map)

  ## Example

      Telemetry.emit_pipeline_start("What is 2+2?", %{preset: :fast})

  """
  @spec emit_pipeline_start(binary(), map() | nil) :: :ok
  def emit_pipeline_start(query, config \\ nil) when is_binary(query) do
    measurements = %{
      system_time: System.system_time()
    }

    metadata = build_pipeline_start_metadata(query, config)

    :telemetry.execute(@pipeline_start_event, measurements, metadata)
  end

  @doc """
  Emits a pipeline stop event.

  ## Parameters

  - `start_time` - The monotonic time when the pipeline started
  - `query` - The query that was processed
  - `result` - The pipeline result

  ## Example

      start_time = System.monotonic_time()
      result = Pipeline.run(pipeline, query, opts)
      Telemetry.emit_pipeline_stop(start_time, query, result)

  """
  @spec emit_pipeline_stop(integer(), binary(), term()) :: :ok
  def emit_pipeline_stop(start_time, query, result) when is_integer(start_time) and is_binary(query) do
    measurements = %{
      duration: System.monotonic_time() - start_time
    }

    metadata = build_pipeline_stop_metadata(query, result)

    :telemetry.execute(@pipeline_stop_event, measurements, metadata)
  end

  @doc """
  Emits a pipeline exception event.

  ## Parameters

  - `start_time` - The monotonic time when the pipeline started
  - `query` - The query being processed
  - `kind` - The exception kind
  - `reason` - The exception reason
  - `stacktrace` - The exception stacktrace (optional)

  ## Example

      try do
        Pipeline.run(pipeline, query, opts)
      rescue
        e -> Telemetry.emit_pipeline_exception(start_time, query, :error, e, __STACKTRACE__)
      end

  """
  @spec emit_pipeline_exception(integer(), binary(), atom(), term(), list()) :: :ok
  def emit_pipeline_exception(start_time, query, kind, reason, stacktrace \\ [])
      when is_integer(start_time) and is_binary(query) and is_atom(kind) do
    measurements = %{
      duration: System.monotonic_time() - start_time
    }

    metadata = %{
      query: query,
      kind: kind,
      reason: format_reason(reason),
      stacktrace: format_stacktrace(stacktrace)
    }

    :telemetry.execute(@pipeline_exception_event, measurements, metadata)
  end

  @doc """
  Emits a stage start event.

  ## Parameters

  - `stage_name` - The name of the stage
  - `query` - The query being processed
  - `stage_config` - The stage configuration (optional)

  ## Example

      Telemetry.emit_stage_start(:generation, "What is 2+2?", %{max_candidates: 5})

  """
  @spec emit_stage_start(atom(), binary(), map() | nil) :: :ok
  def emit_stage_start(stage_name, query, stage_config \\ nil) when is_atom(stage_name) and is_binary(query) do
    measurements = %{
      system_time: System.system_time()
    }

    metadata = build_stage_start_metadata(stage_name, query, stage_config)

    :telemetry.execute(@stage_start_event, measurements, metadata)
  end

  @doc """
  Emits a stage stop event.

  ## Parameters

  - `stage_name` - The name of the stage
  - `start_time` - The monotonic time when the stage started
  - `query` - The query being processed
  - `stage_metadata` - Additional metadata from the stage execution

  ## Example

      start_time = System.monotonic_time()
      result = GenerationStage.execute(input, config)
      Telemetry.emit_stage_stop(:generation, start_time, query, result)

  """
  @spec emit_stage_stop(atom(), integer(), binary(), term()) :: :ok
  def emit_stage_stop(stage_name, start_time, query, stage_metadata)
      when is_atom(stage_name) and is_integer(start_time) and is_binary(query) do
    measurements = %{
      duration: System.monotonic_time() - start_time
    }

    metadata = build_stage_stop_metadata(stage_name, query, stage_metadata)

    :telemetry.execute(@stage_stop_event, measurements, metadata)
  end

  @doc """
  Emits a stage exception event.

  ## Parameters

  - `stage_name` - The name of the stage
  - `start_time` - The monotonic time when the stage started
  - `kind` - The exception kind
  - `reason` - The exception reason
  - `stacktrace` - The exception stacktrace (optional)

  ## Example

      try do
        Stage.execute(input, config)
      rescue
        e -> Telemetry.emit_stage_exception(:generation, start_time, :error, e, __STACKTRACE__)
      end

  """
  @spec emit_stage_exception(atom(), integer(), atom(), term(), list()) :: :ok
  def emit_stage_exception(stage_name, start_time, kind, reason, stacktrace \\ [])
      when is_atom(stage_name) and is_integer(start_time) and is_atom(kind) do
    measurements = %{
      duration: System.monotonic_time() - start_time
    }

    metadata = %{
      stage_name: stage_name,
      kind: kind,
      reason: format_reason(reason),
      stacktrace: format_stacktrace(stacktrace)
    }

    :telemetry.execute(@stage_exception_event, measurements, metadata)
  end

  @doc """
  Wraps pipeline execution in a telemetry span.

  Automatically emits start and stop events. If an exception occurs,
  an exception event is emitted instead.

  ## Parameters

  - `query` - The query being processed
  - `config` - The pipeline configuration
  - `fun` - A zero-arity function that executes the pipeline

  ## Returns

  The result of `fun()`.

  ## Example

      result = Telemetry.pipeline_span(query, config, fn ->
        Pipeline.run(pipeline, query, opts)
      end)

  """
  @spec pipeline_span(binary(), map() | nil, function()) :: term()
  def pipeline_span(query, config, fun) when is_binary(query) and is_function(fun, 0) do
    start_metadata = build_pipeline_start_metadata(query, config)

    :telemetry.span(
      @pipeline_event_prefix,
      start_metadata,
      fn ->
        result = fun.()
        {result, build_pipeline_stop_metadata(query, result)}
      end
    )
  end

  @doc """
  Wraps stage execution in a telemetry span.

  Automatically emits start and stop events. If an exception occurs,
  an exception event is emitted instead.

  ## Parameters

  - `stage_name` - The name of the stage
  - `query` - The query being processed
  - `fun` - A zero-arity function that executes the stage

  ## Returns

  The result of `fun()`.

  ## Example

      result = Telemetry.stage_span(:generation, query, fn ->
        GenerationStage.execute(input, config)
      end)

  """
  @spec stage_span(atom(), binary(), function()) :: term()
  def stage_span(stage_name, query, fun) when is_atom(stage_name) and is_binary(query) and is_function(fun, 0) do
    start_metadata = build_stage_start_metadata(stage_name, query, nil)

    :telemetry.span(
      @stage_event_prefix,
      start_metadata,
      fn ->
        result = fun.()
        {result, build_stage_stop_metadata(stage_name, query, result)}
      end
    )
  end

  @doc """
  Returns the list of event names emitted by this module.

  ## Example

      Telemetry.event_names()
      #=> [
      #=>   [:jido, :accuracy, :pipeline, :start],
      #=>   [:jido, :accuracy, :pipeline, :stop],
      #=>   [:jido, :accuracy, :pipeline, :exception],
      #=>   [:jido, :accuracy, :stage, :start],
      #=>   [:jido, :accuracy, :stage, :stop],
      #=>   [:jido, :accuracy, :stage, :exception]
      #=> ]

  """
  @spec event_names() :: [list(atom())]
  def event_names do
    [
      @pipeline_start_event,
      @pipeline_stop_event,
      @pipeline_exception_event,
      @stage_start_event,
      @stage_stop_event,
      @stage_exception_event
    ]
  end

  # Private Helpers

  defp build_pipeline_start_metadata(query, config) do
    base = %{
      query: query
    }

    preset =
      if is_map(config) do
        Map.get(config, :preset) || Map.get(config, "preset")
      end

    base
    |> maybe_put(:preset, preset)
    |> maybe_put(:config, sanitize_config(config))
  end

  defp build_pipeline_stop_metadata(query, result) do
    base = %{
      query: query
    }

    # Extract result metadata
    result_metadata = extract_result_metadata(result)

    Map.merge(base, result_metadata)
  end

  defp build_stage_start_metadata(stage_name, query, stage_config) do
    base = %{
      stage_name: stage_name,
      query: query
    }

    base
    |> maybe_put(:stage_config, sanitize_config(stage_config))
  end

  defp build_stage_stop_metadata(stage_name, query, stage_result) do
    base = %{
      stage_name: stage_name,
      query: query
    }

    # Extract stage result metadata
    stage_metadata = extract_result_metadata(stage_result)

    Map.merge(base, stage_metadata)
  end

  defp extract_result_metadata(result) when is_map(result) do
    %{}
    |> maybe_put(:status, Map.get(result, :status) || Map.get(result, "status"))
    |> maybe_put(:answer, Map.get(result, :answer) || Map.get(result, "answer"))
    |> maybe_put(:confidence, Map.get(result, :confidence) || Map.get(result, "confidence"))
    |> maybe_put(:num_candidates, get_in(result, [:metadata, :num_candidates]))
    |> maybe_put(:input_tokens, get_in(result, [:metadata, :input_tokens]))
    |> maybe_put(:output_tokens, get_in(result, [:metadata, :output_tokens]))
    |> maybe_put(:total_tokens, calculate_total_tokens(result))
    |> maybe_put(:verification_score, get_in(result, [:metadata, :verification_score]))
    |> maybe_put(:calibration_action, get_in(result, [:metadata, :calibration_action]))
    |> maybe_put(:calibration_level, get_in(result, [:metadata, :calibration_level]))
  end

  defp extract_result_metadata(_result), do: %{}

  defp calculate_total_tokens(result) do
    input = get_in(result, [:metadata, :input_tokens]) || 0
    output = get_in(result, [:metadata, :output_tokens]) || 0

    if input > 0 or output > 0 do
      input + output
    end
  end

  defp format_reason(reason) when is_atom(reason), do: reason
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(%{__exception__: true} = exception), do: Exception.message(exception)
  # For simple tuples, return them as-is
  defp format_reason({_, _} = tuple), do: tuple
  # For complex terms, inspect them
  defp format_reason(reason), do: inspect(reason, limit: 500)

  defp format_stacktrace(nil), do: []
  defp format_stacktrace([]), do: []

  defp format_stacktrace(stacktrace) when is_list(stacktrace) do
    stacktrace
    |> Enum.take(10)
    |> Enum.map(fn
      {module, function, arity, location} ->
        "#{inspect(module)}.#{function}/#{arity} at #{format_location(location)}"

      _other ->
        "unknown"
    end)
  end

  defp format_location(file: file, line: line) when is_integer(line), do: "#{file}:#{line}"
  defp format_location(file: file), do: "#{file}"
  defp format_location(_), do: "unknown"

  defp sanitize_config(nil), do: nil

  defp sanitize_config(config) when is_map(config) do
    # Remove sensitive or large config fields
    config
    |> Map.drop([:generator, :verifiers])
    |> Map.take([:preset, :stages, :telemetry_enabled])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
