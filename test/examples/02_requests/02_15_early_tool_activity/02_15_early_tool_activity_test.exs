defmodule JidoAI.Examples.EarlyToolActivityTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Authoring, Request, Session}
  alias JidoAI.Examples.EarlyToolActivity.{Agent, QuietAgent}

  setup do
    path = Path.join(System.tmp_dir!(), "jido-ai-early-#{Jido.Signal.ID.generate!()}.txt")
    on_exit(fn -> File.rm(path) end)
    old = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model()})

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)

    %{output_path: path}
  end

  defp source do
    {_, options} = Enum.find(Agent.definition().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    Map.from_struct(options[:profiles].assistant)
  end

  defp base,
    do: %{
      name: "early_tool_activity",
      module: Agent,
      vsn: Agent.vsn(),
      schema: Agent.domain_schema(),
      routes: [{"ai.ask", Authoring.ai(:assistant)}]
    }

  defp start(jido, changes \\ %{}) do
    assert {:ok, definition} = Authoring.lower(base(), [Map.merge(source(), changes)])
    start_agent(jido, Jido.Agent.instantiate!(definition))
  end

  defp request(server, context),
    do:
      Request.create_and_send(server, "Write the case",
        signal_type: "ai.ask",
        source: "/examples/early-tool",
        context: context,
        stream_to: self()
      )

  defp events(request),
    do: request |> Request.Stream.events(stream_event_timeout_ms: 1_000) |> Enum.to_list()

  defp first(name \\ "write_document"),
    do: %{
      tool_calls: [
        %{
          index: 0,
          id: "document-call",
          type: "function",
          function: %{name: name, arguments: "{\"body\":\""}
        }
      ]
    }

  defp fragment(text), do: %{tool_calls: [%{index: 0, function: %{arguments: text}}]}

  defp stream(name \\ "write_document"),
    do: %{
      reply:
        {:stream, [first(name), {:wait, :named}, fragment("Case "), {:wait, :body}, fragment("facts\"}")], "tool_calls"}
    }

  defp done, do: %{reply: {:text, ["Draft", " ready"]}}

  defp release(mock) do
    assert :ok = MockLLM.release(mock, :named)
    assert_receive {:mock_llm_waiting, ^mock, :body, _}, 2_000
    assert :ok = MockLLM.release(mock, :body)
  end

  @tag history_case: "HIST-07/early-tool-activity"
  test "named tool activity reaches the public stream before arguments complete or a file is written",
       %{jido: jido, output_path: path} do
    {mock, context} = mock([stream(), done()])
    server = start(jido)
    assert {:ok, request} = request(server, Map.put(context, :output_path, path))
    assert_receive {:mock_llm_waiting, ^mock, :named, _}, 2_000
    id = request.id

    assert_receive {:jido_ai_request_event,
                    %{
                      request_id: ^id,
                      kind: :llm_delta,
                      data: %{chunk_type: :tool_call, delta: "write_document"}
                    } = early},
                   200

    assert early.tool_call_id == nil
    assert Enum.sort(Map.keys(early.data)) == [:chunk_type, :delta, :model]
    refute File.exists?(path)
    refute_receive {:document_started, _}, 0
    release(mock)
    assert {:ok, "Draft ready"} = Request.await(request)
    assert_receive {:document_started, "Case facts"}
    assert File.read!(path) == "Case facts"
    received = [early | events(request)] |> Enum.sort_by(& &1.seq)
    assert Enum.map(received, & &1.seq) == Enum.to_list(1..length(received))
    started = Enum.find(received, &(&1.kind == :tool_started))
    model_done = Enum.find(received, &(&1.kind == :llm_completed))
    assert early.seq < model_done.seq and model_done.seq < started.seq
    assert early.llm_call_id == started.llm_call_id
    assert started.tool_call_id == "document-call"
    [_, followup] = MockLLM.report(mock).requests
    tool_message = Enum.find(followup.body["messages"], &(&1["role"] == "tool"))

    assert Jason.decode!(tool_message["content"]) == %{
             "ok" => true,
             "result" => %{"bytes" => 10, "written" => true}
           }

    content = Enum.filter(received, &(&1.kind == :llm_delta and &1.data.chunk_type == :content))
    assert Enum.all?(content, &(&1.llm_call_id != early.llm_call_id))

    assert content |> Enum.reverse() |> Enum.sort_by(& &1.seq) |> Enum.map_join(& &1.data.delta) ==
             "Draft ready"

    assert_script_done(mock)
  end

  for capture <- [true, false] do
    @tag history_case: "HIST-07/unnamed-fragments"
    test "unnamed argument fragments retain internal activity with capture #{capture}", %{
      jido: jido,
      output_path: path
    } do
      deltas =
        [first()] ++
          Enum.flat_map(1..6, fn n ->
            [{:wait, n}, fragment(if(n == 6, do: "facts\"}", else: "Case "))]
          end)

      {mock, context} = mock([%{reply: {:stream, deltas, "tool_calls"}}, done()])

      server =
        start(jido, %{observability: %{emit_llm_deltas?: unquote(capture)}})

      assert {:ok, request} = request(server, Map.put(context, :output_path, path))
      started = System.monotonic_time(:millisecond)

      for n <- 1..6 do
        assert_receive {:mock_llm_waiting, ^mock, ^n, _}, 2_000
        refute File.exists?(path)
        Process.sleep(120)
        assert :ok = MockLLM.release(mock, n)
      end

      assert {:ok, "Draft ready"} = Request.await(request)
      assert System.monotonic_time(:millisecond) - started >= 700
      assert File.read!(path) == String.duplicate("Case ", 5) <> "facts"
      deltas = Enum.filter(events(request), &(&1.kind == :llm_delta))

      if unquote(capture) do
        tool_deltas = Enum.filter(deltas, &(&1.data.chunk_type == :tool_call))
        assert tool_deltas != []
        assert Enum.all?(tool_deltas, &(&1.data.delta == "write_document"))
        assert Enum.any?(deltas, &(&1.data.chunk_type == :content))
      else
        assert deltas == []
      end

      assert_script_done(mock)
    end
  end

  test "the public legacy delta flag suppresses capture and retains final output and execution",
       %{jido: jido, output_path: path} do
    {mock, context} = mock([stream(), done()])
    server = start_agent(jido, QuietAgent.new!())

    assert {:ok, request} =
             QuietAgent.ask(server, "Write",
               context: Map.put(context, :output_path, path),
               stream_to: self()
             )

    assert_receive {:mock_llm_waiting, ^mock, :named, _}, 2_000
    release(mock)
    assert {:ok, "Draft ready"} = QuietAgent.await(request)
    assert File.read!(path) == "Case facts"
    received = events(request)
    refute Enum.any?(received, &(&1.kind == :llm_delta))
    assert Enum.any?(received, &(&1.kind == :llm_completed))
    assert Enum.any?(received, &(&1.kind == :tool_completed))
    assert_script_done(mock)
  end

  for mode <- [:blocked, :unknown] do
    test "early #{mode} activity does not authorize tool execution", %{
      jido: jido,
      output_path: path
    } do
      name = if unquote(mode) == :unknown, do: "unknown_document", else: "write_document"
      {mock, context} = mock([stream(name)])
      server = start(jido)

      context =
        Map.merge(context, %{output_path: path, block_document: unquote(mode) == :blocked})

      assert {:ok, request} = request(server, context)
      assert_receive {:mock_llm_waiting, ^mock, :named, _}, 2_000
      id = request.id

      assert_receive {:jido_ai_request_event,
                      %{
                        request_id: ^id,
                        kind: :llm_delta,
                        data: %{chunk_type: :tool_call, delta: ^name}
                      }},
                     200

      release(mock)
      assert {:error, _} = Request.await(request)
      refute File.exists?(path)
      refute_receive {:document_started, _}, 0

      refute Enum.any?(
               events(request),
               &(&1.kind in [:tool_started, :tool_completed, :request_completed])
             )

      assert_script_done(mock)
    end
  end

  test "cancellation after early activity closes the provider without document execution", %{
    jido: jido,
    output_path: path
  } do
    {mock, context} = mock([stream()])
    server = start(jido)
    assert {:ok, request} = request(server, Map.put(context, :output_path, path))
    assert_receive {:mock_llm_waiting, ^mock, :named, provider}, 2_000
    monitor = Process.monitor(provider)
    id = request.id

    assert_receive {:jido_ai_request_event, %{request_id: ^id, kind: :llm_delta, data: %{chunk_type: :tool_call}}},
                   200

    assert :ok = Session.cancel(request)
    assert {:error, :cancelled} = Request.await(request)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    refute File.exists?(path)
    refute Enum.any?(events(request), &(&1.kind in [:tool_started, :request_completed]))
    eventually(fn -> MockLLM.report(mock).waiting == [] end)
    assert_script_done(mock)
  end

  test "a disconnected argument stream retains early activity and fails without writing a document",
       %{jido: jido, output_path: path} do
    {mock, context} =
      mock([%{reply: {:stream, [first(), {:wait, :named}, :disconnect], "tool_calls"}}])

    server = start(jido)
    assert {:ok, request} = request(server, Map.put(context, :output_path, path))
    assert_receive {:mock_llm_waiting, ^mock, :named, provider}, 2_000
    monitor = Process.monitor(provider)
    id = request.id

    assert_receive {:jido_ai_request_event, %{request_id: ^id, kind: :llm_delta, data: %{chunk_type: :tool_call}}},
                   200

    assert :ok = MockLLM.release(mock, :named)
    assert {:error, reason} = Request.await(request)
    refute reason in [nil, :cancelled]
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    refute File.exists?(path)
    refute_receive {:document_started, _}, 0
    received = events(request)
    assert List.last(received).kind == :request_failed
    refute Enum.any?(received, &(&1.kind in [:tool_started, :request_completed]))
    assert_script_done(mock)
  end

  test "disabled telemetry still permits enabled public delta capture", %{
    jido: jido,
    output_path: path
  } do
    {mock, context} = mock([stream(), done()])
    server = start(jido, %{observability: %{emit_telemetry?: false, emit_llm_deltas?: true}})
    assert {:ok, request} = request(server, Map.put(context, :output_path, path))
    assert_receive {:mock_llm_waiting, ^mock, :named, _}, 2_000
    id = request.id

    assert_receive {:jido_ai_request_event, %{request_id: ^id, kind: :llm_delta, data: %{chunk_type: :tool_call}}},
                   200

    release(mock)
    assert {:ok, "Draft ready"} = Request.await(request)
    assert File.read!(path) == "Case facts"
    assert_script_done(mock)
  end

  test "DSL data Builder and source JSON retain capture policy and execute the same document tool",
       %{jido: jido, output_path: path} do
    source = source()
    assert {:ok, definition} = Authoring.lower(base(), [source])
    assert definition == Agent.definition()
    attrs = definition |> Map.from_struct() |> Map.drop([:id, :state])
    assert {:ok, built} = attrs |> Jido.Agent.Builder.new() |> Jido.Agent.Builder.build()

    registry =
      source
      |> Map.put(:routes, [])
      |> atoms()
      |> Kernel.++(profile_atoms(source))
      |> Enum.uniq()
      |> Map.new(&{"atoms/#{&1}", {:atom, &1}})
      |> Map.put("models/answer", {:value, source.models.answer.model})

    assert {:ok, document} = Authoring.Codec.encode([source], registry)

    assert {:ok, decoded} =
             Authoring.Codec.decode(base(), Jason.decode!(Jason.encode!(document)), registry)

    assert built == definition
    assert decoded == definition
    quiet = %{source | observability: %{emit_llm_deltas?: false}}
    assert {:ok, quiet_definition} = Authoring.lower(base(), [quiet])
    assert {:ok, quiet_document} = Authoring.Codec.encode([quiet], registry)

    assert {:ok, quiet_decoded} =
             Authoring.Codec.decode(
               base(),
               Jason.decode!(Jason.encode!(quiet_document)),
               registry
             )

    assert quiet_definition == quiet_decoded
    {mock, context} = mock(Enum.flat_map(1..5, fn _ -> [stream(), done()] end))

    for {definition, capture} <- [
          {Agent.definition(), true},
          {definition, true},
          {built, true},
          {decoded, true},
          {quiet_decoded, false}
        ] do
      File.rm(path)
      server = start_agent(jido, Jido.Agent.instantiate!(definition))
      assert {:ok, request} = request(server, Map.put(context, :output_path, path))
      assert_receive {:mock_llm_waiting, ^mock, :named, _}, 2_000
      release(mock)
      assert {:ok, "Draft ready"} = Request.await(request)
      assert File.read!(path) == "Case facts"
      received = events(request)

      assert Enum.any?(received, &(&1.kind == :llm_delta and &1.data.chunk_type == :tool_call)) ==
               capture

      assert Enum.count(received, &(&1.kind == :tool_started)) == 1
      assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    end

    assert_script_done(mock)
  end

  test "invalid delta capture flags fail before activation" do
    for value <- [nil, "false", 0] do
      assert {:error, %{field: "observability"}} =
               Authoring.lower(base(), [%{source() | observability: %{emit_llm_deltas?: value}}])
    end
  end

  test "an empty tool name emits no activity delta and cannot select an executable", %{
    jido: jido,
    output_path: path
  } do
    {mock, context} = mock([stream("")])
    server = start(jido)
    assert {:ok, request} = request(server, Map.put(context, :output_path, path))
    assert_receive {:mock_llm_waiting, ^mock, :named, _}, 2_000
    id = request.id
    refute_receive {:jido_ai_request_event, %{request_id: ^id, kind: :llm_delta}}, 50
    release(mock)
    assert {:error, {:incomplete_response, :tool_calls}} = Request.await(request)
    refute File.exists?(path)

    refute Enum.any?(
             events(request),
             &(&1.kind in [:llm_delta, :llm_completed, :tool_started, :request_completed])
           )

    assert_script_done(mock)
  end

  test "blank successful stops remain distinct from empty declared tool rounds", %{
    jido: jido,
    output_path: path
  } do
    {mock, context} =
      mock([%{reply: {:stream, [], "stop"}}, %{reply: {:stream, [], "tool_calls"}}])

    server = start(jido)
    context = Map.put(context, :output_path, path)
    assert {:ok, first} = request(server, context)
    assert {:ok, ""} = Request.await(first)
    assert Enum.any?(events(first), &(&1.kind == :request_completed))
    assert {:ok, next} = request(server, context)
    assert {:error, {:incomplete_response, :tool_calls}} = Request.await(next)
    assert Server.agent(server).state.requests[next.id].meta.usage.total_tokens == 15

    refute Enum.any?(
             events(next),
             &(&1.kind in [:llm_completed, :tool_started, :request_completed])
           )

    refute File.exists?(path)
    assert_script_done(mock)
  end

  defp atoms(%_{}), do: []
  defp atoms(map) when is_map(map), do: Enum.flat_map(map, fn {k, v} -> atoms(k) ++ atoms(v) end)
  defp atoms(list) when is_list(list), do: Enum.flat_map(list, &atoms/1)
  defp atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> atoms()
  defp atoms(atom) when is_atom(atom), do: [atom]
  defp atoms(_), do: []
  defp eventually(fun, attempts \\ 200)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, attempts),
    do:
      if(fun.(),
        do: :ok,
        else:
          (
            Process.sleep(10)
            eventually(fun, attempts - 1)
          )
      )
end
