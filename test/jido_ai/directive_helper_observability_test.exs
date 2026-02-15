defmodule Jido.AI.DirectiveHelperObservabilityTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Directive.Helper

  test "ensure_required_metadata fills required keys" do
    metadata = Helper.ensure_required_metadata(%{request_id: "req_1", model: "test"})

    assert Map.has_key?(metadata, :agent_id)
    assert Map.has_key?(metadata, :request_id)
    assert Map.has_key?(metadata, :run_id)
    assert Map.has_key?(metadata, :tool_name)
    assert metadata.request_id == "req_1"
    assert metadata.model == "test"
  end

  test "ensure_required_measurements fills required keys" do
    measurements = Helper.ensure_required_measurements(%{duration_ms: 10})

    assert measurements.duration_ms == 10
    assert measurements.input_tokens == 0
    assert measurements.output_tokens == 0
    assert measurements.total_tokens == 0
    assert measurements.retry_count == 0
    assert measurements.queue_ms == 0
  end

  test "emit_react_event executes telemetry without crashing" do
    ref = make_ref()
    handler_id = "directive-helper-obs-test-#{inspect(ref)}"

    :telemetry.attach(
      handler_id,
      [:jido, :ai, :request, :start],
      fn event, measurements, metadata, _ ->
        send(self(), {:telemetry_seen, event, measurements, metadata})
      end,
      nil
    )

    :ok =
      Helper.emit_react_event(
        %{emit_telemetry?: true},
        [:jido, :ai, :request, :start],
        %{duration_ms: 1},
        %{request_id: "req_1", run_id: "req_1"}
      )

    assert_receive {:telemetry_seen, [:jido, :ai, :request, :start], measurements, metadata}
    assert measurements.duration_ms == 1
    assert metadata.request_id == "req_1"
    assert Map.has_key?(metadata, :agent_id)

    :telemetry.detach(handler_id)
  end

  test "emit_react_event does not emit when disabled" do
    ref = make_ref()
    handler_id = "directive-helper-obs-disabled-test-#{inspect(ref)}"

    :telemetry.attach(
      handler_id,
      [:jido, :ai, :request, :start],
      fn event, measurements, metadata, _ ->
        send(self(), {:unexpected_telemetry, event, measurements, metadata})
      end,
      nil
    )

    :ok =
      Helper.emit_react_event(
        %{emit_telemetry?: false},
        [:jido, :ai, :request, :start],
        %{duration_ms: 1},
        %{request_id: "req_1", run_id: "req_1"}
      )

    refute_receive {:unexpected_telemetry, _, _, _}, 50

    :telemetry.detach(handler_id)
  end
end
