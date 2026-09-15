defmodule JidoAI.Examples.TypedSignalsTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Request, Turn}
  alias Jido.AI.Signal
  alias JidoAI.Examples.TypedSignals.{Chat, Echo, Hold, Publisher}
  alias ReqLLM.Message.ContentPart

  @definitions [
    {Signal.EmbedResult, %{call_id: "embedding", result: nil}, "ai.embed.result", "/ai/embed"},
    {Signal.LLMDelta, %{call_id: "model", delta: nil}, "ai.llm.delta", "/ai/llm"},
    {Signal.LLMResponse, %{call_id: "model", result: nil}, "ai.llm.response", "/ai/llm"},
    {Signal.RequestCompleted, %{request_id: "request", result: nil}, "ai.request.completed", "/ai/request"},
    {Signal.RequestError, %{request_id: "request", reason: :busy, message: "Busy"}, "ai.request.error", "/ai/strategy"},
    {Signal.RequestFailed, %{request_id: "request", error: nil}, "ai.request.failed", "/ai/request"},
    {Signal.RequestStarted, %{request_id: "request", query: "Help"}, "ai.request.started", "/ai/request"},
    {Signal.ToolResult, %{call_id: "tool", tool_name: "echo", result: nil}, "ai.tool.result", "/ai/tool"},
    {Signal.ToolStarted, %{call_id: "tool", tool_name: "echo"}, "ai.tool.started", "/ai/tool"},
    {Signal.Usage, %{call_id: "model", model: "fixture", input_tokens: 2, output_tokens: 1}, "ai.usage", "/ai/usage"}
  ]

  defp publisher(jido) do
    assert {:ok, pid} =
             Jido.start_agent(jido, Publisher, default_dispatch: {:pid, target: self()})

    pid
  end

  defp publish(pid, value, context \\ %{}) do
    input = Jido.Signal.new!("ai.event", value, source: "/examples/typed")
    assert {:ok, agent} = Server.call(pid, input, context: context)
    agent
  end

  defp event(kind, data, opts \\ []) do
    Jido.AI.Runtime.Event.new(
      Map.merge(
        %{
          kind: kind,
          data: data,
          seq: 8,
          request_id: "request",
          run_id: "run",
          iteration: 2,
          llm_call_id: "model-call",
          tool_call_id: nil,
          tool_name: nil
        },
        Map.new(opts)
      )
    )
  end

  @tag history_case: "HIST-13/typed-signals"
  test "all ten public Signal definitions validate and pass through real core outbound delivery",
       %{jido: jido} do
    server = publisher(jido)

    for {{module, required, type, source}, count} <- Enum.with_index(@definitions, 1) do
      assert {:ok, signal} = module.new(required)
      assert Map.take(signal.data, Map.keys(required)) == required
      assert signal.type == type and signal.source == source
      assert signal.specversion == "1.0" and signal.time == nil
      assert Jido.Signal.ID.valid?(signal.id)
      assert %Zoi.Types.Map{} = module.schema()
      assert module.__signal_metadata__().schema == module.schema()
      assert module.to_json().extension_policy == %{}
      assert module.datacontenttype() == nil and module.dataschema() == nil
      assert publish(server, %{typed: signal}).state.published == count
      assert_receive {:signal, %Jido.Signal{type: ^type, source: ^source} = delivered}
      assert delivered.data == signal.data
      assert delivered.subject =~ "version-"
    end
  end

  test "all required fields fail through both core constructors when absent" do
    for {module, required, _, _} <- @definitions, field <- Map.keys(required) do
      assert {:error, errors} = module.new(Map.delete(required, field))
      assert Enum.any?(errors, &(&1.path == [field] and &1.code == :required))
      assert_raise Zoi.ParseError, fn -> module.new!(Map.delete(required, field)) end
    end
  end

  test "known string keys normalize once while nested values and shallow map structs remain intact" do
    nested = %{"provider_key" => %{"id" => "004"}, opaque: {:ok, self()}}

    assert {:ok, signal} =
             Signal.LLMResponse.new(%{
               "call_id" => "c",
               "result" => nested,
               "metadata" => MapSet.new([:a])
             })

    assert signal.data.result == nested and signal.data.metadata == MapSet.new([:a])

    for {module, data, _, _} <- @definitions do
      assert module.validate_data(data) ==
               module.validate_data(Map.new(data, fn {k, v} -> {Atom.to_string(k), v} end))
    end
  end

  test "unknown keys and duplicate atom-string aliases cannot overwrite validated fields or create atoms" do
    unknown = "unknown_signal_field_#{Jido.Signal.ID.generate!()}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end

    assert {:error, _} =
             Signal.LLMDelta.new(%{"call_id" => "c", "delta" => "ok", unknown => true})

    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end

    for duplicate <- ["c", "different"] do
      data = %{call_id: "c", delta: "ok"} |> Map.put("call_id", duplicate)
      assert {:error, reason} = Signal.LLMDelta.new(data)
      assert reason =~ "duplicate Signal data field"
      assert_raise ArgumentError, fn -> Signal.LLMDelta.new!(data) end
    end

    assert {:error, _} = Signal.LLMDelta.new(%{{1, 2} => true, call_id: "c", delta: "ok"})
    assert {:error, _} = Signal.LLMDelta.new(call_id: "c", delta: "ok")
  end

  test "omission defaults and explicit nil have distinct public meanings without scalar coercion" do
    assert {:ok, minimal} = Signal.LLMDelta.new(%{call_id: "c", delta: nil})
    assert minimal.data.chunk_type == :content and minimal.data.metadata == %{}
    refute Map.has_key?(minimal.data, :seq)

    assert {:ok, %{data: %{chunk_type: nil}}} =
             Signal.LLMDelta.new(%{call_id: "c", delta: nil, chunk_type: nil})

    for {field, value} <- [
          call_id: nil,
          metadata: nil,
          seq: nil,
          seq: "1",
          run_id: 42,
          iteration: 1.1,
          chunk_type: "content"
        ] do
      assert {:error, _} =
               Signal.LLMDelta.new(Map.put(%{call_id: "c", delta: "ok"}, field, value))
    end

    for {module, field} <- [
          {Signal.LLMResponse, :usage},
          {Signal.LLMResponse, :model},
          {Signal.LLMResponse, :duration_ms},
          {Signal.RequestStarted, :run_id}
        ] do
      {_, data, _, _} = Enum.find(@definitions, &(elem(&1, 0) == module))
      assert {:error, _} = module.new(Map.put(data, field, nil))
    end
  end

  test "core options keep type and validated data fixed and validate envelope overrides" do
    data = %{call_id: "c", delta: "ok"}
    time = "2026-09-06T10:20:30Z"

    assert {:ok, signal} =
             Signal.LLMDelta.new(data,
               source: "/changed",
               subject: "case",
               id: "explicit-id",
               time: time,
               type: "wrong",
               data: %{unvalidated: true}
             )

    assert signal.type == "ai.llm.delta" and signal.data.delta == "ok"
    assert signal.source == "/changed" and signal.subject == "case"
    assert signal.id == "explicit-id" and signal.time == time

    for opts <- [
          [source: "bad source"],
          [time: "yesterday"],
          [id: ""],
          123,
          [:bad],
          %{:source => "/one", "source" => "/two"},
          [data_base64: "YQ=="]
        ] do
      assert {:error, _} = Signal.LLMDelta.new(data, opts)
      assert_raise ArgumentError, fn -> Signal.LLMDelta.new!(data, opts) end
    end

    assert {:ok, last} = Signal.LLMDelta.new(data, source: "/one", source: "/two")
    assert last.source == "/two"
  end

  test "live early tool activity and both model rounds project through core delivery with stable correlation",
       %{jido: jido} do
    first = %{
      tool_calls: [
        %{
          index: 0,
          id: "echo-call",
          type: "function",
          function: %{name: "echo", arguments: "{\"value\":\""}
        }
      ]
    }

    last = %{tool_calls: [%{index: 0, function: %{arguments: "ready\"}"}}]}

    {mock, context} =
      mock([
        %{reply: {:stream, [first, {:wait, :arguments}, last], "tool_calls"}},
        %{reply: {:text, ["Done", " now"]}}
      ])

    server = start_agent(jido, Chat.new!())
    publisher = publisher(jido)

    assert {:ok, request} =
             Request.create_and_send(server, "Echo ready",
               signal_type: "ai.ask",
               source: "/examples/signals",
               context: context,
               stream_to: self()
             )

    assert_receive {:mock_llm_waiting, ^mock, :arguments, _}, 2_000

    assert_receive {:jido_ai_request_event, %{kind: :llm_delta, data: %{chunk_type: :tool_call}} = early},
                   1_000

    refute_received {:jido_ai_request_event, %{kind: :tool_started}}
    publish(publisher, %{event: early})
    assert_receive {:signal, %Jido.Signal{type: "ai.llm.delta"} = delta}
    assert delta.data.delta == "echo" and delta.data.call_id == early.llm_call_id
    assert delta.data.seq == early.seq and delta.data.request_id == request.id
    assert delta.data.run_id == early.run_id and delta.data.iteration == early.iteration
    assert delta.data.metadata.operation == :generate_text
    assert delta.time == DateTime.from_unix!(early.at_ms, :millisecond) |> DateTime.to_iso8601()
    refute Map.has_key?(delta.data, :tool_call_id)
    assert :ok = MockLLM.release(mock, :arguments)
    assert {:ok, "Done now"} = Request.await(request)
    remaining = request |> Request.Stream.events(stream_event_timeout_ms: 1_000) |> Enum.to_list()

    projected =
      Enum.flat_map(remaining, fn event ->
        assert {:ok, expected} = Signal.from_event(event)
        publish(publisher, %{event: event})

        Enum.map(expected, fn expected ->
          type = expected.type
          assert_receive {:signal, %Jido.Signal{type: ^type} = actual}
          assert actual.data == expected.data
          actual
        end)
      end)

    started = Enum.find(projected, &(&1.type == "ai.request.started"))
    assert started.data.query == "Echo ready" and started.data.run_id == early.run_id
    responses = Enum.filter(projected, &(&1.type == "ai.llm.response"))

    assert [
             %{data: %{result: {:ok, %Turn{type: :tool_calls}, []}}},
             %{data: %{result: {:ok, %Turn{text: "Done now"}, []}}}
           ] = responses

    tool = Enum.find(projected, &(&1.type == "ai.tool.result"))
    assert tool.data.call_id == "echo-call" and tool.data.result == {:ok, %{echo: "ready"}, []}
    assert length(Enum.filter(projected, &(&1.type == "ai.usage"))) == 2
    completed = Enum.find(projected, &(&1.type == "ai.request.completed"))
    assert completed.data.result == "Done now" and completed.data.run_id == early.run_id
    text = Enum.filter(projected, &(&1.type == "ai.llm.delta" and &1.data.chunk_type == :content))
    assert Enum.all?(text, &(&1.data.call_id != early.llm_call_id))

    assert text |> Enum.reverse() |> Enum.sort_by(& &1.data.seq) |> Enum.map_join(& &1.data.delta) ==
             "Done now"

    assert_script_done(mock)
  end

  for failure <- [:provider, :cancel] do
    test "live #{failure} failure delivers the stored request outcome through core Signals", %{
      jido: jido
    } do
      reply =
        if unquote(failure) == :provider,
          do: {:error, 503, "Unavailable"},
          else: {:stream, [{:wait, :cancel_provider}], "stop"}

      {mock, context} = mock([%{reply: reply}])
      server = start_agent(jido, Chat.new!())
      publisher = publisher(jido)

      assert {:ok, request} =
               Request.create_and_send(server, "Fail this case",
                 signal_type: "ai.ask",
                 source: "/examples/signals",
                 context: context,
                 stream_to: self()
               )

      if unquote(failure) == :cancel do
        assert_receive {:mock_llm_waiting, ^mock, :cancel_provider, worker}, 2_000
        ref = Process.monitor(worker)
        assert :ok = Jido.AI.Session.cancel(request)
        assert_receive {:DOWN, ^ref, :process, ^worker, _}, 2_000
      end

      assert {:error, failure_value} = Request.await(request)
      events = request |> Request.Stream.events(stream_event_timeout_ms: 1_000) |> Enum.to_list()
      terminal = List.last(events)
      assert terminal.kind in [:request_failed, :request_cancelled]
      publish(publisher, %{event: terminal})
      assert_receive {:signal, %Jido.Signal{type: "ai.request.failed"} = signal}
      assert signal.data.request_id == request.id and signal.data.run_id == terminal.run_id

      if unquote(failure) == :cancel,
        do: assert(signal.data.error == {:cancelled, :cancelled}),
        else: assert(signal.data.error == failure_value)

      assert Server.agent(server).state.requests[request.id].status in [:failed, :cancelled]
      assert_script_done(mock)
    end
  end

  test "the real model response helper and embedding payload retain provider data in delivered Signals",
       %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:text, ["Converted"]}},
        %{match: %{path: "/v1/embeddings"}, reply: {:embeddings, [[0.1, 0.2], [0.3, 0.4]]}}
      ])

    assert {:ok, %{response: response}} =
             Jido.Exec.run(
               Jido.AI.Model.Generate,
               %{
                 model: context.model,
                 messages: "Convert",
                 options: context.model_options,
                 schema: nil,
                 stream: false
               },
               %{}
             )

    assert {:ok, signal} =
             Signal.LLMResponse.from_reqllm_response(response,
               call_id: "response",
               duration_ms: 12
             )

    assert {:ok, %Turn{text: "Converted"}, []} = signal.data.result
    assert signal.data.usage.total_tokens == 15 and signal.data.duration_ms == 12
    assert Signal.LLMResponse.extract_tool_calls(signal) == []

    assert {:ok, vectors} =
             ReqLLM.embed(
               "openai:text-embedding-3-small",
               ["first", "second"],
               Keyword.put(MockLLM.options(mock, :embedding), :return_usage, true)
             )

    embed = Signal.EmbedResult.new!(%{call_id: "embedding", result: {:ok, vectors.embedding}})
    publisher = publisher(jido)
    publish(publisher, %{typed: signal})

    assert_receive {:signal,
                    %{
                      type: "ai.llm.response",
                      data: %{result: {:ok, %Turn{text: "Converted"}, []}}
                    }}

    publish(publisher, %{typed: embed})

    assert_receive {:signal, %{type: "ai.embed.result", data: %{result: {:ok, [[0.1, 0.2], [0.3, 0.4]]}}}}

    assert_script_done(mock)
  end

  test "DSL data Builder and source JSON produce the same projected model and completion Signals",
       %{jido: jido} do
    {_, options} = Enum.find(Chat.definition().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    source = Map.from_struct(options[:profiles].assistant)

    base = %{
      name: "typed_signal_chat",
      module: Chat,
      vsn: Chat.vsn(),
      schema: Chat.domain_schema(),
      routes: [{"ai.ask", Jido.AI.Authoring.ai(:assistant)}]
    }

    assert {:ok, data} = Jido.AI.Authoring.lower(base, [source])
    attrs = data |> Map.from_struct() |> Map.drop([:id, :state])
    assert {:ok, built} = attrs |> Jido.Agent.Builder.new() |> Jido.Agent.Builder.build()

    registry =
      source
      |> Map.put(:routes, [])
      |> atoms()
      |> Kernel.++(profile_atoms(source))
      |> Enum.uniq()
      |> Map.new(&{"atoms/#{&1}", {:atom, &1}})
      |> Map.put("models/answer", {:value, source.models.answer.model})

    assert {:ok, document} = Jido.AI.Authoring.Codec.encode([source], registry)

    assert {:ok, decoded} =
             Jido.AI.Authoring.Codec.decode(
               base,
               Jason.decode!(Jason.encode!(document)),
               registry
             )

    assert Chat.definition() == data and data == built and built == decoded
    {mock, context} = mock(List.duplicate(%{reply: {:text, ["Same answer"]}}, 4))

    for definition <- [Chat.definition(), data, built, decoded] do
      server = start_agent(jido, Jido.Agent.instantiate!(definition))

      assert {:ok, request} =
               Request.create_and_send(server, "Compare",
                 signal_type: "ai.ask",
                 source: "/examples/signals",
                 context: context,
                 stream_to: self()
               )

      assert {:ok, "Same answer"} = Request.await(request)

      signals =
        request
        |> Request.Stream.events(stream_event_timeout_ms: 1_000)
        |> Enum.flat_map(fn event ->
          assert {:ok, signals} = Signal.from_event(event)
          signals
        end)

      assert Enum.any?(
               signals,
               &match?(
                 %{
                   type: "ai.llm.response",
                   data: %{result: {:ok, %Turn{text: "Same answer"}, []}}
                 },
                 &1
               )
             )

      assert Enum.any?(
               signals,
               &match?(%{type: "ai.request.completed", data: %{result: "Same answer"}}, &1)
             )
    end

    assert_script_done(mock)
  end

  defp atoms(%_{}), do: []

  defp atoms(value) when is_map(value),
    do: Enum.flat_map(value, fn {k, v} -> atoms(k) ++ atoms(v) end)

  defp atoms(value) when is_list(value), do: Enum.flat_map(value, &atoms/1)
  defp atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> atoms()
  defp atoms(value) when is_atom(value), do: [value]
  defp atoms(_), do: []

  test "complete content parts and reasoning stay intact through Signal and Turn conversion" do
    image = ContentPart.image(<<0, 255, 2>>, "image/png")
    details = [%{provider: :fixture, signature: "opaque"}]

    event =
      event(:llm_completed, %{
        turn_type: :final_answer,
        text: "Image",
        content_parts: [ContentPart.text("Image"), image],
        reasoning_details: details,
        message_metadata: %{provider: "kept"},
        thinking_content: "Plan",
        usage: %{input_tokens: 2, output_tokens: 3},
        model: "fixture"
      })

    assert {:ok, [%{data: %{result: {:ok, turn, []}}}, _]} = Signal.from_event(event)
    assert Turn.images(turn) == [image] and turn.reasoning_details == details
    assert turn.message_metadata == %{provider: "kept"}
    assert Turn.result(turn) == event.data.content_parts

    assert {:ok, [delta]} =
             Signal.from_event(event(:llm_delta, %{chunk_type: :content_part, delta: image}))

    assert delta.data.delta == image
    assert {:error, _} = Jido.Signal.serialize(delta, format: :json)
  end

  for kind <- [:request_failed, :request_cancelled] do
    test "#{kind} projects the actual run ID and the failure value" do
      event = event(unquote(kind), %{error: {:model, :failed}, reason: :user})
      assert {:ok, [signal]} = Signal.from_event(event)
      assert signal.type == "ai.request.failed" and signal.data.run_id == "run"

      expected =
        if unquote(kind) == :request_failed, do: {:model, :failed}, else: {:cancelled, :user}

      assert signal.data.error == expected
    end
  end

  test "no Signal is invented for keepalive and output-validation events" do
    for kind <- [:keepalive, :llm_started, :output_validated, :checkpoint, :input_injected] do
      assert {:ok, []} = Signal.from_event(event(kind, %{}))
      assert {:ok, []} = Signal.emit(event(kind, %{}))
    end

    assert {:error, :invalid_runtime_event} = Signal.from_event(%{})
    assert {:error, :invalid_signal_options} = Signal.from_event(event(:keepalive, %{}), [:bad])
  end

  test "outbound rejection retains the committed publisher state and does not deliver", %{
    jido: jido
  } do
    server = publisher(jido)

    committed =
      publish(server, %{event: event(:llm_delta, %{delta: "private"})}, %{reject_delivery: true})

    assert committed.state.published == 1
    refute_receive {:signal, _}, 100
    assert Server.agent(server).state.published == 1
  end

  test "direct Turn tools use core validation timeout cleanup and canonical effect results" do
    assert {:ok, %{echo: "direct"}, []} =
             Jido.AI.Tools.Executor.execute("echo", %{"value" => "direct"}, %{observer: self()}, tools: [Echo])

    assert {:error, _, []} = Jido.AI.Tools.Executor.execute_module(Echo, %{}, %{observer: self()})
    parent = self()
    task = Task.async(fn -> Jido.AI.Tools.Executor.execute_module(Hold, %{}, %{observer: parent}, timeout: 80) end)
    assert_receive {:held_action, worker}
    ref = Process.monitor(worker)
    assert {:error, %{type: :timeout, retryable?: false}, []} = Task.await(task)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}
    assert {:error, %{type: :not_found}, []} = Jido.AI.Tools.Executor.execute("unknown", %{}, %{}, tools: [Echo])
  end

  test "direct Turn parameter labels use only declared keyword and Zoi keys and enums" do
    schema = [mode: [type: {:in, [:fast, :slow]}]]

    assert Jido.AI.SchemaInput.normalize_tool(schema, %{"mode" => "fast", "unlisted" => "keep"}) == %{
             "unlisted" => "keep",
             mode: :fast
           }

    zoi = Zoi.object(%{mode: Zoi.enum([:fast, :slow])})
    assert Jido.AI.SchemaInput.normalize_tool(zoi, %{"mode" => "slow"}) == %{mode: :slow}
  end
end
