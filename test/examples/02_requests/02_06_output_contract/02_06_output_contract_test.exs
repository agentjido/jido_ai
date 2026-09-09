defmodule JidoAI.Examples.OutputContractTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Request, Session}
  alias JidoAI.Examples.OutputContract.{Agent, StreamAgent, Schema, Callback}
  alias JidoAI.Examples.OutputContract.{NativeAgent, Telemetry}

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

  defp valid(summary \\ "Refund"), do: %{items: [%{category: "billing", summary: summary}]}

  defp events(request),
    do: request |> Request.Stream.events(stream_event_timeout_ms: 2_000) |> Enum.to_list()

  defp output_events(events),
    do:
      Enum.filter(
        events,
        &(&1.kind in [:output_started, :output_repair, :output_validated, :output_failed])
      )

  @tag history_case: "HIST-11/nested-arrays"
  test "nested objects validate with defaults and enum conversion before completion", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:object, valid()}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Classify", context: context, stream_to: self())

    assert {:ok, %{items: [%{category: :billing, confidence: 1.0, summary: "Refund"}]}} =
             Agent.await(request)

    events = events(request)

    assert Enum.map(output_events(events), &{&1.kind, &1.data.attempt}) == [
             output_started: 0,
             output_validated: 0
           ]

    assert List.last(events).kind == :request_completed
    assert Enum.all?(events, &(&1.request_id == request.id))
    assert length(Enum.uniq_by(events, & &1.run_id)) == 1
    assert Enum.map(events, & &1.seq) == Enum.to_list(1..length(events))
    assert Server.agent(server).state.requests[request.id].meta.output.status == :validated

    assert List.last(events).data.output ==
             Server.agent(server).state.requests[request.id].meta.output

    assert Enum.at(output_events(events), 1).data.schema_summary.properties == ["items"]
    assert_script_done(mock)
  end

  @tag history_case: "HIST-11/finalization"
  test "an Agent without business tools repairs invalid output on the last allowed attempt", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: {:text, "Invalid"}},
        %{reply: {:object, %{items: [%{category: "unknown", summary: "Bad"}]}}},
        %{reply: {:object, valid("Repaired")}}
      ])

    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Classify", context: context, stream_to: self())
    assert {:ok, %{items: [%{summary: "Repaired"}]}} = Agent.await(request)
    events = events(request)

    assert Enum.map(output_events(events), &{&1.kind, &1.data.attempt}) ==
             [output_started: 0, output_repair: 1, output_repair: 2, output_validated: 2]

    record = Server.agent(server).state.requests[request.id]
    assert record.meta.output.status == :repaired
    assert record.meta.output.raw_preview == "Invalid"
    assert record.meta.output.validation_error
    assert record.meta.model_calls == 3
    assert record.meta.usage.total_tokens == 45
    assert List.last(events).data.output == record.meta.output
    assert_script_done(mock)
  end

  for {name, opts} <- [
        {"error mode", [on_validation_error: :error, retries: 2]},
        {"zero retries", [retries: 0]}
      ] do
    @tag history_case: "HIST-11/finalization"
    test "#{name} fails validation without a repair call", %{jido: jido} do
      {mock, context} = mock([%{reply: {:object, %{items: [42]}}}])
      server = start_agent(jido, Agent.new!())
      output = [schema: Schema.output()] ++ unquote(opts)

      assert {:ok, request} =
               Agent.ask(server, "Classify", context: context, stream_to: self(), output: output)

      assert {:error, _} = Agent.await(request)
      events = events(request)

      assert Enum.map(output_events(events), &{&1.kind, &1.data.attempt}) == [
               output_started: 0,
               output_failed: 0
             ]

      assert List.last(events).kind == :request_failed
      record = Server.agent(server).state.requests[request.id]
      assert record.meta.output.status == :error
      assert record.meta.output.error
      assert record.meta.usage.total_tokens == 15
      assert Server.agent(server).state.last_result == nil
      assert_script_done(mock)
    end
  end

  test "repair exhaustion emits one output failure and retains failed output metadata", %{
    jido: jido
  } do
    {mock, context} = mock(List.duplicate(%{reply: {:object, %{items: [42]}}}, 3))
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Classify", context: context, stream_to: self())
    assert {:error, _} = Agent.await(request)
    events = events(request)

    assert Enum.map(output_events(events), &{&1.kind, &1.data.attempt}) ==
             [output_started: 0, output_repair: 1, output_repair: 2, output_failed: 2]

    assert List.last(events).kind == :request_failed
    record = Server.agent(server).state.requests[request.id]
    assert record.meta.output.status == :error
    assert record.meta.output.attempt == 2
    assert record.meta.usage.total_tokens == 45
    assert_script_done(mock)
  end

  @tag history_case: "HIST-11/raw-bypass"
  test "raw output has no stale output events or metadata on later requests", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:object, valid()}}, %{reply: {:text, "Raw"}}, %{reply: {:object, valid()}}])

    server = start_agent(jido, Agent.new!())
    assert {:ok, _} = Agent.ask_sync(server, "Typed", context: context)

    assert {:ok, request} =
             Agent.ask(server, "Raw", context: context, output: :raw, stream_to: self())

    assert {:ok, "Raw"} = Agent.await(request)
    assert output_events(events(request)) == []
    refute Map.has_key?(Server.agent(server).state.requests[request.id].meta, :output)
    assert {:ok, %{items: [_]}} = Agent.ask_sync(server, "Typed again", context: context)
    assert_script_done(mock)
  end

  @tag history_case: "HIST-11/stream-input"
  test "streamed thinking and a tool round do not enter the final JSON text", %{jido: jido} do
    json = Jason.encode!(valid())
    split = div(byte_size(json), 2)

    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "lookup", name: "scope_echo", arguments: %{value: 9}}]}},
        %{
          reply:
            {:stream,
             [
               %{reasoning_content: "Synthetic fixture reasoning"},
               %{content: binary_part(json, 0, split)},
               %{content: binary_part(json, split, byte_size(json) - split)}
             ]}
        }
      ])

    server = start_agent(jido, StreamAgent.new!())

    assert {:ok, request} =
             StreamAgent.ask(server, "Classify", context: context, stream_to: self())

    assert {:ok, %{items: [%{category: :billing}]}} = StreamAgent.await(request)
    events = events(request)
    assert Enum.map(output_events(events), & &1.kind) == [:output_started, :output_validated]
    assert Enum.any?(events, &(&1.kind == :llm_delta && &1.data[:chunk_type] == :thinking))
    assert length(MockLLM.report(mock).requests) == 2
    assert_script_done(mock)
  end

  test "provider schema tools finalize output without executing a business tool", %{jido: jido} do
    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model("gpt-4.1-mini")})

    {mock, context} =
      mock([%{reply: {:tools, [%{id: "schema", name: "structured_output", arguments: valid()}]}}])

    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Classify", context: context, stream_to: self())
    assert {:ok, %{items: [_]}} = Agent.await(request)
    events = events(request)
    refute Enum.any?(events, &(&1.kind == :tool_started))
    assert Enum.map(output_events(events), & &1.kind) == [:output_started, :output_validated]
    assert_script_done(mock)
  end

  test "a provider error during repair retains the output attempt and available usage", %{
    jido: jido
  } do
    {mock, context} =
      mock([%{reply: {:text, "Invalid"}}, %{reply: {:error, 503, "Repair unavailable"}}])

    server = start_agent(jido, Agent.new!())
    id = observe()

    assert {:ok, request} =
             Agent.ask(server, "Classify",
               context: context,
               stream_to: self(),
               request_id: id,
               output: [schema: Schema.output(), retries: 1]
             )

    assert {:error, _} = Agent.await(request)
    events = events(request)

    assert Enum.map(output_events(events), &{&1.kind, &1.data.attempt}) ==
             [output_started: 0, output_repair: 1, output_failed: 1]

    record = Server.agent(server).state.requests[request.id]
    assert record.meta.output.status == :error
    assert record.meta.usage.total_tokens == 15
    assert_receive {:observed, [:jido, :ai, :output, :error], _, %{request_id: ^id, attempt: 1}}
    assert_script_done(mock)
  end

  for outcome <- [:recover, :exhaust] do
    test "provider repair attempts #{outcome} at the declared limit", %{jido: jido} do
      last =
        if unquote(outcome) == :recover,
          do: {:object, valid("Recovered")},
          else: {:error, 503, "Still unavailable"}

      {mock, context} =
        mock([
          %{reply: {:text, "Invalid"}},
          %{reply: {:error, 503, "Temporary failure"}},
          %{reply: last}
        ])

      server = start_agent(jido, Agent.new!())
      assert {:ok, request} = Agent.ask(server, "Classify", context: context, stream_to: self())
      result = Agent.await(request)
      record = Server.agent(server).state.requests[request.id]
      received = events(request)
      assert record.meta.model_calls == 3
      assert record.meta.output.attempt == 2
      assert length(MockLLM.report(mock).requests) == 3

      assert Enum.map(Enum.filter(received, &(&1.kind == :output_repair)), & &1.data.attempt) == [
               1,
               2
             ]

      if unquote(outcome) == :recover do
        assert {:ok, %{items: [%{summary: "Recovered"}]}} = result
        assert record.status == :completed and record.meta.output.status == :repaired
        assert record.meta.usage.total_tokens == 30
        refute Enum.any?(received, &(&1.kind == :output_failed))
      else
        assert {:error, _} = result
        assert record.status == :failed and record.meta.output.status == :error
        assert record.meta.usage.total_tokens == 15
        assert Enum.count(received, &(&1.kind == :output_failed)) == 1
      end

      assert {:ok, %{live: nil}} = Session.snapshot(server)
      assert_script_done(mock)
    end
  end

  test "cancelling a held repair stops its task and commits output failure metadata", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:text, "Invalid"}}])
    server = start_agent(jido, Agent.new!())

    assert {:ok, request} =
             Agent.ask(server, "Classify",
               context: context,
               stream_to: self(),
               output: [schema: Schema.output(), repair_fun: {Callback, :wait}]
             )

    assert_receive {:repair_waiting, worker}, 2_000
    monitor = Process.monitor(worker)
    assert :ok = Session.cancel(request)
    assert {:error, :cancelled} = Agent.await(request)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    events = events(request)

    assert Enum.map(output_events(events), &{&1.kind, &1.data.attempt}) ==
             [output_started: 0, output_repair: 1, output_failed: 1]

    assert List.last(events).kind == :request_cancelled
    assert Server.agent(server).state.requests[request.id].meta.output.status == :error
    assert_script_done(mock)
  end

  @tag history_case: "HIST-11/output-events"
  test "output telemetry is correlated and has no model payload", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Invalid"}}, %{reply: {:object, valid()}}])
    id = observe()
    server = start_agent(jido, Agent.new!())

    assert {:ok, request} =
             Agent.ask(server, "Classify", context: context, request_id: id, stream_to: self())

    assert {:ok, _} = Agent.await(request)
    events(request)
    assert_receive {:observed, [:jido, :ai, :output, :start], measurements, meta}
    assert meta.request_id == id
    assert meta.operation == :structured_output
    assert meta.attempt == 0
    assert is_binary(meta.agent_id)
    assert is_binary(meta.llm_call_id)
    assert Map.has_key?(measurements, :duration_ms)
    refute Map.has_key?(meta, :raw_preview)
    refute Map.has_key?(meta, :result)
    assert_receive {:observed, [:jido, :ai, :output, :repair], _, %{attempt: 1}}
    assert_receive {:observed, [:jido, :ai, :output, :validated], _, %{attempt: 1}}
    assert_receive {:observed, [:jido, :ai, :request, :complete], %{total_tokens: 30}, _}
    assert_script_done(mock)
  end

  test "DSL, data, Builder and JSON keep output telemetry while disabling delta capture", %{
    jido: jido
  } do
    source = NativeAgent.source()
    assert {:ok, direct} = Jido.AI.Authoring.lower(NativeAgent.base(), [source])
    assert direct == NativeAgent.definition()
    attrs = direct |> Map.from_struct() |> Map.drop([:id, :state])
    built = Jido.Agent.Builder.new(attrs) |> Jido.Agent.Builder.build!()
    registry = source_registry(source)
    assert {:ok, document} = Jido.AI.Authoring.Codec.encode([source], registry)
    document = document |> Jason.encode!() |> Jason.decode!()
    assert {:ok, decoded} = Jido.AI.Authoring.Codec.decode(NativeAgent.base(), document, registry)
    assert decoded == direct
    {mock, context} = mock(List.duplicate(%{reply: {:object, valid()}}, 4))

    for definition <- [NativeAgent.definition(), direct, built, decoded] do
      id = observe()
      server = start_agent(jido, Jido.Agent.instantiate!(definition))

      assert {:ok, request} =
               Request.create_and_send(server, "Classify",
                 context: context,
                 request_id: id,
                 signal_type: "ai.ask",
                 source: "/examples/ai/output",
                 stream_to: self()
               )

      assert {:ok, %{items: [_]}} = Request.await(request)
      refute Enum.any?(events(request), &(&1.kind == :llm_delta))
      assert_receive {:observed, [:jido, :ai, :output, :validated], _, %{request_id: ^id}}
      refute_receive {:observed, [:jido, :ai, :llm, :delta], _, %{request_id: ^id}}, 0
    end

    assert_script_done(mock)
  end

  test "disabled telemetry keeps request events and invalid flags fail before admission", %{
    jido: jido
  } do
    source = %{NativeAgent.source() | observability: %{emit_telemetry?: false}}
    assert {:ok, definition} = Jido.AI.Authoring.lower(NativeAgent.base(), [source])
    {mock, context} = mock([%{reply: {:object, valid()}}])
    id = observe()
    server = start_agent(jido, Jido.Agent.instantiate!(definition))

    assert {:ok, request} =
             Request.create_and_send(server, "Classify",
               context: context,
               request_id: id,
               signal_type: "ai.ask",
               source: "/examples/ai/output",
               stream_to: self()
             )

    assert {:ok, _} = Request.await(request)

    assert Enum.map(output_events(events(request)), & &1.kind) == [
             :output_started,
             :output_validated
           ]

    refute_receive {:observed, _, _, %{request_id: ^id}}, 0

    assert {:error, _} =
             Jido.AI.Authoring.lower(NativeAgent.base(), [
               %{source | observability: %{emit_telemetry?: "false"}}
             ])

    assert_script_done(mock)
  end

  test "a rejected domain result retains output and usage metadata", %{jido: jido} do
    source = NativeAgent.source()
    # The result satisfies the AI schema but violates the independent domain schema.
    base = %{NativeAgent.base() | schema: Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})}
    assert {:ok, definition} = Jido.AI.Authoring.lower(base, [source])
    {mock, context} = mock([%{reply: {:object, valid()}}])
    server = start_agent(jido, Jido.Agent.instantiate!(definition))

    assert {:ok, request} =
             Request.create_and_send(server, "Classify",
               context: context,
               signal_type: "ai.ask",
               source: "/examples/ai/output",
               stream_to: self()
             )

    assert {:error, :invalid_domain_result} = Request.await(request)

    assert Enum.map(output_events(events(request)), & &1.kind) == [
             :output_started,
             :output_validated,
             :output_failed
           ]

    record = Server.agent(server).state.requests[request.id]
    assert record.meta.output.status == :error
    assert record.meta.usage.total_tokens == 15
    assert Server.agent(server).state.reply == ""
    assert_script_done(mock)
  end

  test "validated event previews redact map keys and bound Unicode values", %{jido: jido} do
    schema = Zoi.object(%{api_key: Zoi.string(), text: Zoi.string()})
    texts = ["short", String.duplicate("é", 800)]

    {mock, context} =
      mock(for text <- texts, do: %{reply: {:object, %{api_key: "fixture-secret", text: text}}})

    server = start_agent(jido, Agent.new!())

    for text <- texts do
      assert {:ok, request} =
               Agent.ask(server, "Classify",
                 context: context,
                 stream_to: self(),
                 output: [schema: schema]
               )

      assert {:ok, %{api_key: "fixture-secret"}} = Agent.await(request)
      event = Enum.find(events(request), &(&1.kind == :output_validated))
      assert String.valid?(event.data.raw_preview)
      assert String.length(event.data.raw_preview) <= 500
      if text == "short", do: assert(event.data.raw_preview =~ "[REDACTED]")
      refute event.data.raw_preview =~ "fixture-secret"
    end

    assert_script_done(mock)
  end

  test "an output control rejection fails after validation and preserves the domain result", %{
    jido: jido
  } do
    source =
      Map.put(NativeAgent.source(), :controls, %{output: [JidoAI.Examples.OutputContract.Reject]})

    assert {:ok, definition} = Jido.AI.Authoring.lower(NativeAgent.base(), [source])
    {mock, context} = mock([%{reply: {:object, valid()}}])
    server = start_agent(jido, Jido.Agent.instantiate!(definition))

    assert {:ok, request} =
             Request.create_and_send(server, "Classify",
               context: context,
               signal_type: "ai.ask",
               source: "/examples/ai/output",
               stream_to: self()
             )

    assert {:error, _} = Request.await(request)

    assert Enum.map(output_events(events(request)), & &1.kind) == [
             :output_started,
             :output_validated,
             :output_failed
           ]

    assert Server.agent(server).state.requests[request.id].meta.output.status == :error
    assert Server.agent(server).state.reply == %{}
    assert_script_done(mock)
  end

  test "the outer deadline stops a held callback and records one output failure", %{jido: jido} do
    source =
      NativeAgent.source()
      |> Map.put(:controls, %{timeout: 1_000})
      |> put_in([:result, :max_repairs], 1)
      |> put_in([:result, :repair_fun], {Callback, :wait})

    assert {:ok, definition} = Jido.AI.Authoring.lower(NativeAgent.base(), [source])
    {mock, context} = mock([%{reply: {:text, "Invalid"}}])
    server = start_agent(jido, Jido.Agent.instantiate!(definition))

    assert {:ok, request} =
             Request.create_and_send(server, "Classify",
               context: context,
               signal_type: "ai.ask",
               source: "/examples/ai/output",
               stream_to: self()
             )

    assert_receive {:repair_waiting, worker}, 2_000
    monitor = Process.monitor(worker)
    assert {:error, _} = Request.await(request, timeout: 3_000)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000

    assert Enum.map(output_events(events(request)), &{&1.kind, &1.data.attempt}) ==
             [output_started: 0, output_repair: 1, output_failed: 1]

    record = Server.agent(server).state.requests[request.id]
    assert record.meta.output.status == :error
    assert record.meta.usage.total_tokens == 15
    assert_script_done(mock)
  end

  defp observe do
    id = "output-#{System.unique_integer([:positive])}"

    names =
      for {family, phases} <- [
            output: [:start, :repair, :validated, :error],
            request: [:complete],
            llm: [:delta]
          ],
          phase <- phases,
          do: [:jido, :ai, family, phase]

    :ok =
      :telemetry.attach_many(id, names, &Telemetry.handle/4, %{observer: self(), request_id: id})

    on_exit(fn -> :telemetry.detach(id) end)
    id
  end

  defp source_registry(source) do
    atoms = [
      :id,
      :assistant,
      :instructions,
      :models,
      :answer,
      :example,
      :model,
      :generation,
      :reasoning,
      :method,
      :react,
      :tool_concurrency,
      :controls,
      :input,
      :operation,
      :output,
      :max_iterations,
      :max_model_calls,
      :max_tool_calls,
      :timeout,
      :tools,
      :result,
      :schema,
      :into,
      :reply,
      :max_repairs,
      :requests,
      :mode,
      :session,
      :on_busy,
      :reject,
      :max_requests,
      :streaming,
      :steering,
      :memory,
      :history,
      :observability,
      :effect_policy,
      :emit_llm_deltas?,
      :routes
    ]

    entries =
      atoms
      |> Kernel.++(profile_atoms(source))
      |> Enum.uniq()
      |> Map.new(&{"atoms/#{&1}", {:atom, &1}})
      |> Map.put("schema/output", {:value, source.result.schema})

    Jido.Agent.Codec.Registry.new!(entries)
  end
end
