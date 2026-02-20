defmodule Jido.AI.ObserveTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Observe

  test "ensure_required_metadata fills required keys" do
    metadata = Observe.ensure_required_metadata(%{request_id: "req_1", model: "test"})

    assert Map.has_key?(metadata, :agent_id)
    assert Map.has_key?(metadata, :request_id)
    assert Map.has_key?(metadata, :run_id)
    assert Map.has_key?(metadata, :tool_name)
    assert metadata.request_id == "req_1"
    assert metadata.model == "test"
  end

  test "ensure_required_measurements fills required keys" do
    measurements = Observe.ensure_required_measurements(%{duration_ms: 10})

    assert measurements.duration_ms == 10
    assert measurements.input_tokens == 0
    assert measurements.output_tokens == 0
    assert measurements.total_tokens == 0
    assert measurements.retry_count == 0
    assert measurements.queue_ms == 0
  end

  test "sanitize_sensitive redacts sensitive key variants" do
    payload = %{
      "api_key" => "k1",
      "apikey" => "k2",
      "clientsecret" => "k3",
      "secret_value" => "k4",
      "session_token" => "k5",
      "PASSWORD" => "k6",
      :access_key => "k7",
      "username" => "alice"
    }

    sanitized = Observe.sanitize_sensitive(payload)

    assert sanitized["api_key"] == "[REDACTED]"
    assert sanitized["apikey"] == "[REDACTED]"
    assert sanitized["clientsecret"] == "[REDACTED]"
    assert sanitized["secret_value"] == "[REDACTED]"
    assert sanitized["session_token"] == "[REDACTED]"
    assert sanitized["PASSWORD"] == "[REDACTED]"
    assert sanitized[:access_key] == "[REDACTED]"
    assert sanitized["username"] == "alice"
  end

  test "emit executes telemetry with normalized shape" do
    ref = make_ref()
    handler_id = "observe-test-emit-#{inspect(ref)}"

    :telemetry.attach(
      handler_id,
      Observe.request(:start),
      fn event, measurements, metadata, _ ->
        send(self(), {:telemetry_seen, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok =
      Observe.emit(
        %{emit_telemetry?: true},
        Observe.request(:start),
        %{duration_ms: 1},
        %{request_id: "req_1", run_id: "req_1"}
      )

    assert_receive {:telemetry_seen, event, measurements, metadata}
    assert event == Observe.request(:start)
    assert measurements.duration_ms == 1
    assert metadata.request_id == "req_1"
    assert Map.has_key?(metadata, :agent_id)
  end

  test "emit does not emit telemetry when disabled" do
    ref = make_ref()
    handler_id = "observe-test-disabled-#{inspect(ref)}"

    :telemetry.attach(
      handler_id,
      Observe.request(:start),
      fn event, measurements, metadata, _ ->
        send(self(), {:unexpected_telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok =
      Observe.emit(
        %{emit_telemetry?: false},
        Observe.request(:start),
        %{duration_ms: 1},
        %{request_id: "req_1", run_id: "req_1"}
      )

    refute_receive {:unexpected_telemetry, _, _, _}, 50
  end

  test "feature-gated llm deltas are suppressed when disabled" do
    ref = make_ref()
    handler_id = "observe-test-delta-gate-#{inspect(ref)}"

    :telemetry.attach(
      handler_id,
      Observe.llm(:delta),
      fn event, measurements, metadata, _ ->
        send(self(), {:unexpected_delta, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok =
      Observe.emit(
        %{emit_telemetry?: true, emit_llm_deltas?: false},
        Observe.llm(:delta),
        %{duration_ms: 0},
        %{request_id: "req_1", llm_call_id: "call_1"},
        feature_gate: :llm_deltas
      )

    refute_receive {:unexpected_delta, _, _, _}, 50
  end

  test "span wrappers are no-op when telemetry disabled" do
    ref = make_ref()
    handler_id = "observe-test-span-disabled-#{inspect(ref)}"

    :telemetry.attach_many(
      handler_id,
      [Observe.llm(:span) ++ [:start], Observe.llm(:span) ++ [:stop], Observe.llm(:span) ++ [:exception]],
      fn event, measurements, metadata, _ ->
        send(self(), {:unexpected_span_event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    span_ctx = Observe.start_span(%{emit_telemetry?: false}, Observe.llm(:span), %{request_id: "req_1"})
    assert span_ctx == :noop
    assert :ok = Observe.finish_span(span_ctx, %{duration_ms: 1})
    refute_receive {:unexpected_span_event, _, _, _}, 50
  end
end
