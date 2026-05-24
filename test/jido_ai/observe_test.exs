defmodule Jido.AI.ObserveTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Observe

  test "ensure_required_metadata fills required keys" do
    metadata = Observe.ensure_required_metadata(%{request_id: "req_1", model: "test"})

    assert Map.has_key?(metadata, :agent_id)
    assert Map.has_key?(metadata, :request_id)
    assert Map.has_key?(metadata, :run_id)
    assert Map.has_key?(metadata, :tool_name)
    assert Map.has_key?(metadata, :origin)
    assert Map.has_key?(metadata, :operation)
    assert Map.has_key?(metadata, :strategy)
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

  test "sanitize_sensitive redacts nested maps and lists recursively" do
    payload = %{
      profile: %{
        display_name: "alice",
        api_secret: "s1",
        nested: [%{"session_token" => "s2"}, %{ok: true}]
      },
      notes: ["safe", %{private_key: "s3"}]
    }

    sanitized = Observe.sanitize_sensitive(payload)

    assert sanitized.profile.display_name == "alice"
    assert sanitized.profile.api_secret == "[REDACTED]"
    assert Enum.at(sanitized.profile.nested, 0)["session_token"] == "[REDACTED]"
    assert Enum.at(sanitized.profile.nested, 1).ok == true
    assert Enum.at(sanitized.notes, 0) == "safe"
    assert Enum.at(sanitized.notes, 1).private_key == "[REDACTED]"
  end

  test "sanitize_telemetry_metadata redacts, bounds, and summarizes payload fields" do
    metadata = %{
      request_id: "req_1",
      params: %{
        "api_key" => "secret",
        "query" => String.duplicate("x", 20)
      },
      result:
        {:error,
         %{
           type: :timeout,
           message: String.duplicate("timeout ", 10),
           details: %{token: "secret"}
         }, []},
      tags: Enum.to_list(1..6)
    }

    sanitized =
      Observe.sanitize_telemetry_metadata(metadata,
        max_string_chars: 12,
        max_list_items: 3
      )

    assert sanitized.params["api_key"] == "[REDACTED]"
    assert sanitized.params["query"] == "xxxxxxxxxxxx...[truncated]"

    assert sanitized.result.status == :error
    assert sanitized.result.error.type == :timeout
    assert sanitized.result.error.message == "timeout time...[truncated]"
    refute match?({:error, _, _}, sanitized.result)

    assert Enum.take(sanitized.tags, 3) == [1, 2, 3]
    assert List.last(sanitized.tags) == %{__jido_ai_truncated__: %{omitted_items: 3}}
  end

  test "sanitize_telemetry_metadata does not inspect unexpected payload terms" do
    sanitized =
      Observe.sanitize_telemetry_metadata(%{
        result: {:unexpected, %{api_key: "secret", value: "visible"}}
      })

    assert sanitized.result == %{type: :tuple, size: 2}
    refute inspect(sanitized) =~ "secret"
    refute inspect(sanitized) =~ "visible"
  end

  test "sanitize_transport_payload produces bounded JSON-safe data" do
    payload = %{
      ok: true,
      result: %{
        password: "secret",
        tuple: {:ok, self()},
        callback: fn -> :ok end,
        text: String.duplicate("a", 16)
      }
    }

    sanitized = Observe.sanitize_transport_payload(payload, max_string_chars: 8)

    assert sanitized.result.password == "[REDACTED]"
    assert sanitized.result.tuple.type == :tuple
    assert sanitized.result.tuple.size == 2
    assert sanitized.result.callback.type == :function
    assert sanitized.result.text == "aaaaaaaa...[truncated]"
    assert {:ok, _json} = Jason.encode(sanitized)
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

  test "emit sanitizes telemetry metadata before delivery" do
    ref = make_ref()
    handler_id = "observe-test-emit-sanitize-#{inspect(ref)}"

    :telemetry.attach(
      handler_id,
      Observe.request(:complete),
      fn _event, _measurements, metadata, _ ->
        send(self(), {:telemetry_seen, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok =
      Observe.emit(
        %{emit_telemetry?: true},
        Observe.request(:complete),
        %{duration_ms: 1},
        %{
          request_id: "req_1",
          api_key: "secret",
          result: {:ok, %{payload: String.duplicate("x", 1_000)}, []}
        }
      )

    assert_receive {:telemetry_seen, metadata}
    assert metadata.api_key == "[REDACTED]"
    assert metadata.result.status == :ok
    assert metadata.result.value.type == :map
    refute match?({:ok, _, _}, metadata.result)
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

  test "feature-gated llm deltas emit when enabled" do
    ref = make_ref()
    handler_id = "observe-test-delta-enabled-#{inspect(ref)}"

    :telemetry.attach(
      handler_id,
      Observe.llm(:delta),
      fn event, measurements, metadata, _ ->
        send(self(), {:delta_seen, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok =
      Observe.emit(
        %{emit_telemetry?: true, emit_llm_deltas?: true},
        Observe.llm(:delta),
        %{duration_ms: 2},
        %{request_id: "req_2", llm_call_id: "call_2"},
        feature_gate: :llm_deltas
      )

    assert_receive {:delta_seen, event, measurements, metadata}
    assert event == Observe.llm(:delta)
    assert measurements.duration_ms == 2
    assert measurements.input_tokens == 0
    assert metadata.request_id == "req_2"
    assert metadata.llm_call_id == "call_2"
    assert Map.has_key?(metadata, :agent_id)
    assert Map.has_key?(metadata, :run_id)
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
