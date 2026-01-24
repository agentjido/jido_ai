defmodule Jido.AI.Accuracy.TelemetryTest do
  @moduledoc """
  Tests for the Telemetry module.
  """

  use ExUnit.Case, async: false

  alias Jido.AI.Accuracy.Telemetry

  @moduletag :telemetry

  # Setup and teardown for all tests
  setup_all do
    # Create a registry to track all handlers
    {:ok, registry_pid} = Agent.start_link(fn -> MapSet.new() end)

    %{registry: registry_pid}
  end

  setup %{registry: registry_pid} do
    # Create a fresh collector for each test
    {:ok, collector_pid} = Agent.start_link(fn -> [] end)

    on_exit(fn ->
      # Clean up: stop the collector last to ensure all handlers are detached first
      Process.sleep(5)
    end)

    %{collector: collector_pid, registry: registry_pid}
  end

  describe "event_names/0" do
    test "returns all event names" do
      events = Telemetry.event_names()

      assert [:jido, :accuracy, :pipeline, :start] in events
      assert [:jido, :accuracy, :pipeline, :stop] in events
      assert [:jido, :accuracy, :pipeline, :exception] in events
      assert [:jido, :accuracy, :stage, :start] in events
      assert [:jido, :accuracy, :stage, :stop] in events
      assert [:jido, :accuracy, :stage, :exception] in events
      assert length(events) == 6
    end
  end

  describe "emit_pipeline_start/2" do
    test "emits pipeline start event with measurements", %{collector: collector_pid} do
      handler_id = attach_collector(collector_pid, [:jido, :accuracy, :pipeline, :start])

      query = "What is 2+2?"
      config = %{preset: :fast}

      Telemetry.emit_pipeline_start(query, config)

      # Allow event to be processed
      Process.sleep(10)
      events = collect_events(collector_pid)

      assert length(events) == 1
      assert [_event, measurements, metadata] = List.first(events)

      assert Map.has_key?(measurements, :system_time)
      assert is_integer(measurements.system_time)
      assert metadata.query == query
      assert metadata.preset == :fast

      :telemetry.detach(handler_id)
    end

    test "emits pipeline start event without config", %{collector: collector_pid} do
      handler_id = attach_collector(collector_pid, [:jido, :accuracy, :pipeline, :start])

      query = "What is 2+2?"

      Telemetry.emit_pipeline_start(query)

      Process.sleep(10)
      events = collect_events(collector_pid)

      assert [_event, _measurements, metadata] = List.first(events)
      assert metadata.query == query
      refute Map.has_key?(metadata, :preset)

      :telemetry.detach(handler_id)
    end
  end

  describe "emit_pipeline_stop/3" do
    test "emits pipeline stop event with duration", %{collector: collector_pid} do
      handler_id = attach_collector(collector_pid, [:jido, :accuracy, :pipeline, :stop])

      start_time = System.monotonic_time()
      query = "What is 2+2?"
      result = %{answer: "4", confidence: 0.95}

      Process.sleep(5)
      Telemetry.emit_pipeline_stop(start_time, query, result)

      Process.sleep(10)
      events = collect_events(collector_pid)

      assert [_event, measurements, metadata] = List.first(events)

      assert measurements.duration > 0
      assert is_integer(measurements.duration)
      assert metadata.query == query
      assert metadata.answer == "4"
      assert metadata.confidence == 0.95

      :telemetry.detach(handler_id)
    end

    test "includes token usage in metadata when present", %{collector: collector_pid} do
      handler_id = attach_collector(collector_pid, [:jido, :accuracy, :pipeline, :stop])

      start_time = System.monotonic_time()
      query = "What is 2+2?"

      result = %{
        answer: "4",
        metadata: %{
          input_tokens: 100,
          output_tokens: 50,
          num_candidates: 3
        }
      }

      Telemetry.emit_pipeline_stop(start_time, query, result)

      Process.sleep(10)
      events = collect_events(collector_pid)

      assert [_event, _measurements, metadata] = List.first(events)

      assert metadata.input_tokens == 100
      assert metadata.output_tokens == 50
      assert metadata.total_tokens == 150
      assert metadata.num_candidates == 3

      :telemetry.detach(handler_id)
    end

    test "includes verification score in metadata when present", %{collector: collector_pid} do
      handler_id = attach_collector(collector_pid, [:jido, :accuracy, :pipeline, :stop])

      start_time = System.monotonic_time()
      query = "What is 2+2?"

      result = %{
        answer: "4",
        metadata: %{
          verification_score: 0.9
        }
      }

      Telemetry.emit_pipeline_stop(start_time, query, result)

      Process.sleep(10)
      events = collect_events(collector_pid)

      assert [_event, _measurements, metadata] = List.first(events)

      assert metadata.verification_score == 0.9

      :telemetry.detach(handler_id)
    end
  end

  describe "emit_pipeline_exception/5" do
    test "emits pipeline exception event", %{collector: collector_pid} do
      handler_id = attach_collector(collector_pid, [:jido, :accuracy, :pipeline, :exception])

      start_time = System.monotonic_time()
      query = "What is 2+2?"
      kind = :error
      reason = {:error, :generator_failed}

      Telemetry.emit_pipeline_exception(start_time, query, kind, reason)

      Process.sleep(10)
      events = collect_events(collector_pid)

      assert [_event, measurements, metadata] = List.first(events)

      assert measurements.duration > 0
      assert metadata.query == query
      assert metadata.kind == :error
      assert metadata.reason == {:error, :generator_failed}

      :telemetry.detach(handler_id)
    end

    test "formats exception reason", %{collector: collector_pid} do
      handler_id = attach_collector(collector_pid, [:jido, :accuracy, :pipeline, :exception])

      start_time = System.monotonic_time()
      query = "What is 2+2?"

      try do
        raise "Test error"
      rescue
        e ->
          Telemetry.emit_pipeline_exception(start_time, query, :error, e, __STACKTRACE__)
      end

      Process.sleep(10)
      events = collect_events(collector_pid)

      assert [_event, _measurements, metadata] = List.first(events)

      assert is_binary(metadata.reason)
      assert metadata.reason =~ "Test error"

      :telemetry.detach(handler_id)
    end

    test "includes stacktrace when provided", %{collector: collector_pid} do
      handler_id = attach_collector(collector_pid, [:jido, :accuracy, :pipeline, :exception])

      start_time = System.monotonic_time()
      query = "What is 2+2?"
      stacktrace = [{Jido.AI.Accuracy.Telemetry, :test_function, 1, [file: "test.exs", line: 10]}]

      Telemetry.emit_pipeline_exception(start_time, query, :error, :test_error, stacktrace)

      Process.sleep(10)
      events = collect_events(collector_pid)

      assert [_event, _measurements, metadata] = List.first(events)

      assert is_list(metadata.stacktrace)
      refute Enum.empty?(metadata.stacktrace)

      :telemetry.detach(handler_id)
    end
  end

  describe "emit_stage_start/3" do
    test "emits stage start event", %{collector: collector_pid} do
      handler_id = attach_collector(collector_pid, [:jido, :accuracy, :stage, :start])

      stage_name = :generation
      query = "What is 2+2?"
      stage_config = %{max_candidates: 5}

      Telemetry.emit_stage_start(stage_name, query, stage_config)

      Process.sleep(10)
      events = collect_events(collector_pid)

      assert [_event, measurements, metadata] = List.first(events)

      assert Map.has_key?(measurements, :system_time)
      assert metadata.stage_name == :generation
      assert metadata.query == query

      :telemetry.detach(handler_id)
    end

    test "emits stage start event without config", %{collector: collector_pid} do
      handler_id = attach_collector(collector_pid, [:jido, :accuracy, :stage, :start])

      stage_name = :verification
      query = "What is 2+2?"

      Telemetry.emit_stage_start(stage_name, query)

      Process.sleep(10)
      events = collect_events(collector_pid)

      assert [_event, _measurements, metadata] = List.first(events)

      assert metadata.stage_name == :verification
      refute Map.has_key?(metadata, :stage_config)

      :telemetry.detach(handler_id)
    end
  end

  describe "emit_stage_stop/4" do
    test "emits stage stop event with duration", %{collector: collector_pid} do
      handler_id = attach_collector(collector_pid, [:jido, :accuracy, :stage, :stop])

      start_time = System.monotonic_time()
      stage_name = :generation
      query = "What is 2+2?"
      stage_result = %{candidates: ["Answer 1", "Answer 2"]}

      Process.sleep(5)
      Telemetry.emit_stage_stop(stage_name, start_time, query, stage_result)

      Process.sleep(10)
      events = collect_events(collector_pid)

      assert [_event, measurements, metadata] = List.first(events)

      assert measurements.duration > 0
      assert metadata.stage_name == :generation
      assert metadata.query == query

      :telemetry.detach(handler_id)
    end

    test "includes metadata from stage result", %{collector: collector_pid} do
      handler_id = attach_collector(collector_pid, [:jido, :accuracy, :stage, :stop])

      start_time = System.monotonic_time()
      stage_name = :generation
      query = "What is 2+2?"

      stage_result = %{
        candidates: ["Answer 1"],
        metadata: %{
          num_candidates: 3,
          input_tokens: 50
        }
      }

      Telemetry.emit_stage_stop(stage_name, start_time, query, stage_result)

      Process.sleep(10)
      events = collect_events(collector_pid)

      assert [_event, _measurements, metadata] = List.first(events)

      assert metadata.num_candidates == 3
      assert metadata.input_tokens == 50

      :telemetry.detach(handler_id)
    end
  end

  describe "emit_stage_exception/5" do
    test "emits stage exception event", %{collector: collector_pid} do
      handler_id = attach_collector(collector_pid, [:jido, :accuracy, :stage, :exception])

      start_time = System.monotonic_time()
      stage_name = :generation
      kind = :error
      reason = {:generation_failed, :timeout}

      Telemetry.emit_stage_exception(stage_name, start_time, kind, reason)

      Process.sleep(10)
      events = collect_events(collector_pid)

      assert [_event, measurements, metadata] = List.first(events)

      assert measurements.duration > 0
      assert metadata.stage_name == :generation
      assert metadata.kind == :error

      :telemetry.detach(handler_id)
    end
  end

  describe "pipeline_span/3" do
    test "wraps pipeline execution and emits start/stop events", %{collector: collector_pid} do
      start_handler_id =
        attach_collector(collector_pid, [:jido, :accuracy, :pipeline, :start])

      stop_handler_id = attach_collector(collector_pid, [:jido, :accuracy, :pipeline, :stop])

      query = "What is 2+2?"
      config = %{preset: :fast}

      result =
        Telemetry.pipeline_span(query, config, fn ->
          %{answer: "4", confidence: 0.95}
        end)

      assert result.answer == "4"

      Process.sleep(10)

      # Check events
      events = collect_events(collector_pid)

      # Should have both start and stop events
      assert length(events) == 2

      start_events = Enum.filter(events, fn [event | _] -> event == [:jido, :accuracy, :pipeline, :start] end)
      stop_events = Enum.filter(events, fn [event | _] -> event == [:jido, :accuracy, :pipeline, :stop] end)

      assert [_start_event, _start_measurements, start_metadata] = List.first(start_events)
      assert start_metadata.query == query
      assert start_metadata.preset == :fast

      assert [_stop_event, stop_measurements, stop_metadata] = List.first(stop_events)
      assert stop_measurements.duration > 0
      assert stop_metadata.query == query
      assert stop_metadata.answer == "4"

      :telemetry.detach(start_handler_id)
      :telemetry.detach(stop_handler_id)
    end

    test "re-raises exceptions and emits start but not stop event", %{collector: collector_pid} do
      start_handler_id =
        attach_collector(collector_pid, [:jido, :accuracy, :pipeline, :start])

      stop_handler_id =
        attach_collector(collector_pid, [:jido, :accuracy, :pipeline, :stop])

      query = "What is 2+2?"
      config = %{preset: :fast}

      assert_raise RuntimeError, "test error", fn ->
        Telemetry.pipeline_span(query, config, fn ->
          raise "test error"
        end)
      end

      Process.sleep(10)

      # Check events - should have start but not stop (due to exception)
      events = collect_events(collector_pid)

      start_events = Enum.filter(events, fn [event | _] -> event == [:jido, :accuracy, :pipeline, :start] end)
      stop_events = Enum.filter(events, fn [event | _] -> event == [:jido, :accuracy, :pipeline, :stop] end)

      # Should have start event
      assert length(start_events) == 1
      # Should NOT have stop event (function raised)
      assert Enum.empty?(stop_events)

      :telemetry.detach(start_handler_id)
      :telemetry.detach(stop_handler_id)
    end
  end

  describe "stage_span/3" do
    test "wraps stage execution and emits start/stop events", %{collector: collector_pid} do
      start_handler_id = attach_collector(collector_pid, [:jido, :accuracy, :stage, :start])
      stop_handler_id = attach_collector(collector_pid, [:jido, :accuracy, :stage, :stop])

      stage_name = :generation
      query = "What is 2+2?"

      result =
        Telemetry.stage_span(stage_name, query, fn ->
          %{candidates: ["Answer 1", "Answer 2"]}
        end)

      assert length(result.candidates) == 2

      Process.sleep(10)

      # Check events
      events = collect_events(collector_pid)

      start_events = Enum.filter(events, fn [event | _] -> event == [:jido, :accuracy, :stage, :start] end)
      stop_events = Enum.filter(events, fn [event | _] -> event == [:jido, :accuracy, :stage, :stop] end)

      assert [_start_event, _start_measurements, start_metadata] = List.first(start_events)
      assert start_metadata.stage_name == :generation
      assert start_metadata.query == query

      assert [_stop_event, stop_measurements, stop_metadata] = List.first(stop_events)
      assert stop_measurements.duration > 0
      assert stop_metadata.stage_name == :generation

      :telemetry.detach(start_handler_id)
      :telemetry.detach(stop_handler_id)
    end

    test "re-raises exceptions and emits start but not stop event", %{collector: collector_pid} do
      start_handler_id = attach_collector(collector_pid, [:jido, :accuracy, :stage, :start])
      stop_handler_id = attach_collector(collector_pid, [:jido, :accuracy, :stage, :stop])

      stage_name = :generation
      query = "What is 2+2?"

      assert_raise RuntimeError, "stage error", fn ->
        Telemetry.stage_span(stage_name, query, fn ->
          raise "stage error"
        end)
      end

      Process.sleep(10)

      # Check events - should have start but not stop (due to exception)
      events = collect_events(collector_pid)

      start_events = Enum.filter(events, fn [event | _] -> event == [:jido, :accuracy, :stage, :start] end)
      stop_events = Enum.filter(events, fn [event | _] -> event == [:jido, :accuracy, :stage, :stop] end)

      # Should have start event
      assert length(start_events) == 1
      # Should NOT have stop event (function raised)
      assert Enum.empty?(stop_events)

      :telemetry.detach(start_handler_id)
      :telemetry.detach(stop_handler_id)
    end
  end

  describe "Integration Tests" do
    test "complete pipeline execution flow", %{collector: collector_pid} do
      # Attach to all relevant events
      handler_ids = [
        attach_collector(collector_pid, [:jido, :accuracy, :pipeline, :start]),
        attach_collector(collector_pid, [:jido, :accuracy, :pipeline, :stop]),
        attach_collector(collector_pid, [:jido, :accuracy, :stage, :start]),
        attach_collector(collector_pid, [:jido, :accuracy, :stage, :stop])
      ]

      query = "What is 2+2?"
      config = %{preset: :fast}

      # Pipeline start
      Telemetry.emit_pipeline_start(query, config)

      # Stage 1: generation
      start_time = System.monotonic_time()
      Telemetry.emit_stage_start(:generation, query, %{max_candidates: 3})
      Process.sleep(2)

      Telemetry.emit_stage_stop(:generation, start_time, query, %{
        candidates: ["4"],
        metadata: %{num_candidates: 3}
      })

      # Stage 2: calibration
      start_time = System.monotonic_time()
      Telemetry.emit_stage_start(:calibration, query, nil)
      Process.sleep(2)

      Telemetry.emit_stage_stop(:calibration, start_time, query, %{
        answer: "4",
        confidence: 0.95,
        metadata: %{calibration_action: :direct, calibration_level: :high}
      })

      # Pipeline stop
      pipeline_start = System.monotonic_time() - 10

      Telemetry.emit_pipeline_stop(pipeline_start, query, %{
        answer: "4",
        confidence: 0.95,
        metadata: %{
          num_candidates: 3,
          total_tokens: 100,
          calibration_action: :direct
        }
      })

      # Wait for events to be processed
      Process.sleep(20)

      # Verify events
      events = collect_events(collector_pid)

      # Should have at least 6 events
      assert length(events) >= 6

      # Verify we have the expected events
      event_names = Enum.map(events, fn [event | _] -> event end)

      assert [:jido, :accuracy, :pipeline, :start] in event_names
      assert [:jido, :accuracy, :stage, :start] in event_names
      assert [:jido, :accuracy, :stage, :stop] in event_names
      assert [:jido, :accuracy, :pipeline, :stop] in event_names

      # Detach all handlers
      Enum.each(handler_ids, &:telemetry.detach/1)
    end
  end

  # Test Helpers

  defp attach_collector(collector_pid, event_name) do
    handler_id = make_ref()

    :telemetry.attach(
      handler_id,
      event_name,
      fn event, measurements, metadata, _config ->
        try do
          Agent.update(collector_pid, fn events ->
            [[event, measurements, metadata] | events]
          end)
        rescue
          # Collector may be stopped, ignore error
          _ -> :ok
        end
      end,
      nil
    )

    handler_id
  end

  defp collect_events(collector_pid) do
    Agent.get(collector_pid, fn events ->
      Enum.reverse(events)
    end)
  end
end
