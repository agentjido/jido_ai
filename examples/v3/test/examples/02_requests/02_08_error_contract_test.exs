defmodule JidoAI.Examples.ErrorContractTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Error, Request}
  alias JidoAI.Examples.ErrorContract.{Agent, TransformAgent, NativeAgent}

  setup do
    old = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model()})

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)
  end

  defp events(request),
    do: request |> Request.Stream.events(stream_event_timeout_ms: 2_000) |> Enum.to_list()

  defp record(server, request), do: Server.agent(server).state.requests[request.id]

  defp failure(details),
    do: %{
      type: :repair_unavailable,
      message: "Fixture repair failure",
      details: details,
      retryable?: false
    }

  @tag history_case: "HIST-14/raw-failure"
  test "portable repair errors reach await and terminal events without display conversion", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:object, %{answer: 42}}}])
    raw = failure(%{cause: {:upstream, :unavailable}, attempt: 1})
    server = start_agent(jido, Agent.new!())

    assert {:ok, request} =
             Agent.ask(server, "Repair",
               context: Map.put(context, :failure, raw),
               stream_to: self()
             )

    assert {:error, ^raw} = Agent.await(request, timeout: 2_000)
    saved = record(server, request)
    assert saved.error == raw
    assert saved.meta.output.status == :error
    assert saved.meta.usage.total_tokens == 15
    assert_receive {:repair_called, _}
    refute_receive {:repair_called, _}, 20
    responses = events(request)
    assert Enum.count(responses, &(&1.kind == :output_failed)) == 1
    assert List.last(responses).kind == :request_failed
    assert List.last(responses).data.error == raw
    assert List.last(responses).data.meta == saved.meta
    assert Server.agent(server).state.last_result == nil
    assert is_binary(Server.agent(server).state.last_answer)
    assert_script_done(mock)
  end

  @tag history_case: "HIST-14/error-details"
  test "arbitrary repair error details produce a committed failure with portable metadata", %{
    jido: jido
  } do
    {mock, context} =
      mock([%{reply: {:object, %{answer: 42}}}, %{reply: {:object, %{answer: "Next"}}}])

    raw =
      failure(%{
        7 => "numeric key",
        worker: self(),
        ref: make_ref(),
        callback: fn -> :unused end,
        cause: {:upstream, %{step: 3}},
        improper: [1 | 2],
        nested: %{error: ArgumentError.exception("Nested fixture")},
        api_key: "fixture-secret"
      })

    server = start_agent(jido, Agent.new!())

    assert {:ok, request} =
             Agent.ask(server, "Repair",
               context: Map.put(context, :failure, raw),
               stream_to: self()
             )

    assert {:error, error} = Agent.await(request, timeout: 2_000)
    assert error.type == :repair_unavailable
    assert error.message == "Fixture repair failure"
    assert error.retryable? == false
    assert is_binary(error.details.worker)
    assert is_binary(error.details.ref)
    assert is_binary(error.details.callback)
    assert is_binary(error.details.improper)
    assert error.details["7"] == "numeric key"
    assert error.details.nested.error.message == "Nested fixture"
    assert Jason.encode!(error)
    saved = record(server, request)
    assert saved.status == :failed
    assert saved.error == error
    assert saved.meta.output.status == :error
    assert saved.meta.output.error.api_key == "[REDACTED]"
    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    assert Jason.encode!(saved.meta)
    responses = events(request)
    assert Enum.count(responses, &(&1.kind == :output_failed)) == 1
    assert List.last(responses).data.error == error
    assert List.last(responses).data.meta == saved.meta
    assert {:ok, %{answer: "Next"}} = Agent.ask_sync(server, "Next", context: context)
    assert_script_done(mock)
  end

  @tag history_case: "HIST-14/raw-failure"
  test "portable transformer failures keep their wrapper before any HTTP request", %{jido: jido} do
    {mock, context} = mock([])
    raw = failure(%{stage: :credential_refresh})
    server = start_agent(jido, TransformAgent.new!())

    assert {:ok, request} =
             TransformAgent.ask(server, "Answer",
               context: Map.put(context, :failure, raw),
               stream_to: self()
             )

    assert {:error, {:request_transformer, ^raw}} = TransformAgent.await(request)
    assert List.last(events(request)).data.error == {:request_transformer, raw}
    assert MockLLM.report(mock).requests == []
    assert_script_done(mock)
  end

  test "provider failures keep status and cause through the public request API", %{jido: jido} do
    {mock, context} = mock([%{reply: {:error, 503, "Fixture provider unavailable"}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Answer", context: context, stream_to: self())
    assert {:error, error} = Agent.await(request)
    assert is_map(error)
    assert error.details.status == 503
    assert error.details.cause.status == 503
    assert error.message =~ "Fixture provider unavailable"
    assert error.details.response_body["error"]["message"] == "Fixture provider unavailable"
    assert Jason.encode!(error)
    assert record(server, request).error == error
    responses = events(request)
    assert List.last(responses).kind == :request_failed
    assert List.last(responses).data.error == error
    refute Enum.any?(responses, &(&1.kind == :output_started))
    assert_script_done(mock)
  end

  test "a nonportable transformer cause keeps its failure wrapper and converted details", %{
    jido: jido
  } do
    {mock, context} = mock([])
    raw = failure(%{credential_process: self()})
    server = start_agent(jido, TransformAgent.new!())

    assert {:ok, request} =
             TransformAgent.ask(server, "Answer", context: Map.put(context, :failure, raw))

    assert {:error, {:request_transformer, error}} = TransformAgent.await(request)
    assert error.type == :repair_unavailable
    assert is_binary(error.details.credential_process)
    assert :ok = Jido.Action.validate_static_data(record(server, request))
    assert MockLLM.report(mock).requests == []
    assert_script_done(mock)
  end

  for source <- [:action, :core] do
    @tag history_case: "HIST-14/instruction-details"
    test "a failing control preserves the #{source} error constructor details", %{jido: jido} do
      {mock, context} = mock([%{reply: {:object, %{answer: "Rejected"}}}])
      server = start_agent(jido, NativeAgent.new!())

      assert {:ok, request} =
               Request.create_and_send(server, "Answer",
                 signal_type: "ai.ask",
                 source: "/examples/errors",
                 context: Map.put(context, :failure_mode, unquote(source)),
                 stream_to: self()
               )

      assert {:error, error} = Request.await(request)
      assert is_exception(error)
      assert error.details.value == "Rejected"
      assert error.details.reason == :policy_rejected
      normalized = Error.normalize(error)
      assert normalized.details.value == "Rejected"
      assert normalized.details.reason == :policy_rejected
      assert normalized.retryable? == Jido.Error.to_map(error).retryable?
      assert Error.retryable?(error) == normalized.retryable?
      assert Jason.encode!(normalized)
      assert List.last(events(request)).data.error == error
      assert Server.agent(server).state.reply == %{}
      assert_script_done(mock)
    end
  end

  test "a killed repair process becomes a committed failure with its core cause", %{jido: jido} do
    {mock, context} = mock([%{reply: {:object, %{answer: 42}}}])
    server = start_agent(jido, Agent.new!())

    assert {:ok, request} =
             Agent.ask(server, "Repair",
               context: Map.put(context, :failure_mode, :kill),
               stream_to: self()
             )

    assert_receive {:repair_called, _}, 2_000
    assert {:error, error} = Agent.await(request, timeout: 2_000)
    assert is_exception(error)
    assert inspect(Error.normalize(error)) =~ "killed"
    saved = record(server, request)
    assert saved.status == :failed
    assert saved.meta.output.status == :error
    assert saved.meta.usage.total_tokens == 15
    responses = events(request)
    assert Enum.count(responses, &(&1.kind == :output_failed)) == 1
    assert List.last(responses).data.error == error
    assert List.last(responses).data.meta == saved.meta
    assert_script_done(mock)
  end

  for mode <- [:raise, :exit] do
    test "repair callback #{mode} becomes one committed output failure", %{jido: jido} do
      {mock, context} = mock([%{reply: {:object, %{answer: 42}}}])
      server = start_agent(jido, Agent.new!())

      assert {:ok, request} =
               Agent.ask(server, "Repair",
                 context: Map.put(context, :failure_mode, unquote(mode)),
                 stream_to: self()
               )

      assert {:error, error} = Agent.await(request, timeout: 2_000)

      case unquote(mode) do
        :raise ->
          assert %Error.Validation.Output{} = error
          assert error.details.reason == {:repair_exception, "Fixture repair exception"}

        :exit ->
          assert error == {:exit, :fixture_exit}
      end

      saved = record(server, request)
      assert saved.status == :failed
      assert saved.meta.output.status == :error
      responses = events(request)
      assert Enum.count(responses, &(&1.kind == :output_failed)) == 1
      assert List.last(responses).data.error == error
      assert List.last(responses).data.meta == saved.meta
      assert :ok = Jido.Action.validate_static_data(saved)
      assert_script_done(mock)
    end
  end

  for portable? <- [true, false] do
    test "native DSL output controls retain failures with portable=#{portable?} details", %{
      jido: jido
    } do
      {mock, context} =
        mock([
          %{reply: {:object, %{answer: "Blocked"}}},
          %{reply: {:object, %{answer: "Allowed"}}}
        ])

      details =
        if unquote(portable?), do: %{policy: :rejected}, else: %{policy: :rejected, owner: self()}

      raw = failure(details)
      server = start_agent(jido, NativeAgent.new!())

      assert {:ok, request} =
               Request.create_and_send(server, "Answer",
                 signal_type: "ai.ask",
                 source: "/examples/errors",
                 context: Map.put(context, :failure, raw),
                 stream_to: self()
               )

      assert {:error, error} = Request.await(request, timeout: 2_000)
      assert error == Error.for_storage(raw)
      assert error.details.policy == :rejected
      assert Server.agent(server).state.reply == %{}
      responses = events(request)

      assert Enum.map(
               Enum.filter(
                 responses,
                 &(&1.kind in [:output_validated, :output_failed, :request_failed])
               ),
               & &1.kind
             ) == [:output_validated, :output_failed, :request_failed]

      assert record(server, request).meta.output.status == :error
      assert List.last(responses).data.error == error
      assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)

      assert {:ok, next} =
               Request.create_and_send(server, "Next",
                 signal_type: "ai.ask",
                 source: "/examples/errors",
                 context: context
               )

      assert {:ok, %{answer: "Allowed"}} = Request.await(next)
      assert_script_done(mock)
    end
  end

  @tag history_case: "HIST-14/error-details"
  test "invalid UTF-8 in error messages keys and values uses a JSON-safe representation", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:object, %{answer: 42}}}])
    bytes = <<255, 0, 254>>
    raw = %{failure(%{bytes => bytes, :owner => self(), :nested => [bytes]}) | message: bytes}
    server = start_agent(jido, Agent.new!())

    assert {:ok, request} =
             Agent.ask(server, "Repair",
               context: Map.put(context, :failure, raw),
               stream_to: self()
             )

    assert {:error, error} = Agent.await(request)
    encoded = "base64:" <> Base.encode64(bytes)
    assert error.message == encoded
    assert error.details[encoded] == encoded
    assert error.details.nested == [encoded]
    assert Jason.encode!(error)
    assert Jason.encode!(record(server, request).meta)
    assert List.last(events(request)).data.error == error
    assert Error.error_envelope(:fixture, bytes, %{bytes => bytes}).message == encoded
    assert_script_done(mock)
  end

  @tag history_case: "HIST-14/json-restore"
  test "encoded error maps retain known types and explicit retry hints without creating atoms" do
    for hint <- [false, "false", " FALSE ", "off"] do
      raw = %{"type" => "timeout", "message" => "Timed out", "details" => %{"retry" => hint}}
      decoded = raw |> Jason.encode!() |> Jason.decode!() |> Error.normalize()
      assert decoded.type == :timeout
      refute decoded.retryable?
      refute Error.retryable?(decoded)
    end

    name = "untrusted_error_#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    error = Error.normalize(%{"type" => name, "message" => nil, "details" => %{}})
    assert error.type == :execution_error
    assert error.message == "Execution failed"
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end

    assert Error.normalize({:error, %{type: :timeout, message: "Wrapped", retryable?: false}}).message ==
             "Wrapped"
  end

  test "output error summaries terminate for null fields and redact bounded payloads", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:object, %{answer: 42}}}])
    nested = Enum.reduce(1..7, %{type: nil, message: nil}, fn _, acc -> %{next: acc} end)

    raw =
      failure(%{nested: nested, note: String.duplicate("界", 20_000), api_key: "fixture-secret"})

    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Repair", context: Map.put(context, :failure, raw))
    assert {:error, ^raw} = Agent.await(request, timeout: 2_000)
    summary = record(server, request).meta.output.error
    assert summary.api_key == "[REDACTED]"
    assert String.length(summary.note) < 17_000
    assert Jason.encode!(summary)
    invalid_key = Jido.AI.Observe.sanitize_transport_payload(%{<<255>> => "Value"})
    assert Jason.encode!(invalid_key)
    assert_script_done(mock)
  end
end
