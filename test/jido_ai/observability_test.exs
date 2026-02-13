defmodule Jido.AI.ObservabilityTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Observability
  alias Jido.AI.Observability.OTel

  test "ensure_required_metadata fills required keys" do
    metadata = Observability.ensure_required_metadata(%{request_id: "req_1", model: "test"})

    assert Map.has_key?(metadata, :agent_id)
    assert Map.has_key?(metadata, :request_id)
    assert Map.has_key?(metadata, :run_id)
    assert Map.has_key?(metadata, :tool_name)
    assert metadata.request_id == "req_1"
    assert metadata.model == "test"
  end

  test "ensure_required_measurements fills required keys" do
    measurements = Observability.ensure_required_measurements(%{duration_ms: 10})

    assert measurements.duration_ms == 10
    assert measurements.input_tokens == 0
    assert measurements.output_tokens == 0
    assert measurements.total_tokens == 0
    assert measurements.retry_count == 0
    assert measurements.queue_ms == 0
  end

  test "emit executes telemetry without crashing" do
    ref = make_ref()

    :telemetry.attach(
      "obs-test-#{inspect(ref)}",
      [:jido, :ai, :react, :request, :start],
      fn event, measurements, metadata, _ ->
        send(self(), {:telemetry_seen, event, measurements, metadata})
      end,
      nil
    )

    :ok =
      Observability.emit(
        [:jido, :ai, :react, :request, :start],
        %{duration_ms: 1},
        %{request_id: "req_1", run_id: "req_1"}
      )

    assert_receive {:telemetry_seen, [:jido, :ai, :react, :request, :start], measurements, metadata}
    assert measurements.duration_ms == 1
    assert metadata.request_id == "req_1"

    :telemetry.detach("obs-test-#{inspect(ref)}")
  end

  test "otel bridge is safe no-op" do
    assert :ok == OTel.handle_telemetry_event([:jido, :ai, :react, :request, :start], %{}, %{})
  end
end
