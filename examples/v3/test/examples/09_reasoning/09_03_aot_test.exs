defmodule JidoAI.Examples.AoTTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Authoring, Request, Session}
  alias Jido.AI.Reasoning.AlgorithmOfThoughts, as: Method
  alias JidoAI.Examples.AoT

  setup do
    saved = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model()})

    on_exit(fn ->
      case saved do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)

    :ok
  end

  defp start(jido, changes \\ %{}) do
    assert {:ok, definition} = AoT.definition(changes)

    assert {:ok, server} =
             Jido.start_agent(jido, Jido.Agent.instantiate!(definition),
               default_dispatch: {:pid, target: self()}
             )

    server
  end

  defp request(server, context, query \\ "8 6 4 4"),
    do:
      Request.create_and_send(server, query,
        signal_type: "ai.aot.query",
        source: "/examples/aot",
        context: context,
        stream_to: self()
      )

  defp record(server, request), do: Server.agent(server).state.requests[request.id]

  defp events(request),
    do: request |> Request.Stream.events(stream_event_timeout_ms: 1_000) |> Enum.to_list()

  defp options(value),
    do: %{
      reasoning: %{
        AoT.source().reasoning
        | options: Map.merge(AoT.source().reasoning.options, value)
      }
    }

  defp eventually(fun, n \\ 300)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, n) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(10)
          eventually(fun, n - 1)
        )
  end

  defp delivered(server, request) do
    eventually(fn ->
      match?({:ok, %{status: :delivered}}, Session.delivery_status(server, request.id))
    end)

    signals()
  end

  defp signals(acc \\ []) do
    receive do
      {:signal, signal} -> signals([signal | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "AoT keeps the number puzzle result metrics and one real model call", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, AoT.puzzle()}}])
    server = start(jido)
    assert {:ok, request} = request(server, context)
    assert {:ok, result} = Request.await(request)
    assert result.answer == "(4 + (8 - 6)) * 4 = 24"
    assert result.first_operations_considered == 1 and result.backtracking_steps == 3
    assert result.found_solution? and result.raw_response == AoT.puzzle()
    assert result.usage.total_tokens == 15
    assert %{reason: :success, status: :completed, duration_ms: n} = result.termination
    assert n >= 0
    assert_receive {:aot_checked, ^result}
    assert Method.get_result(Server.agent(server), request.id) == result
    assert Server.agent(server).state.reply == result
    assert record(server, request).meta.model_calls == 1
    assert record(server, request).meta.tool_calls == 0
    assert record(server, request).method == Method.method()
    assert_script_done(mock)
  end

  test "all AoT prompt profiles and search styles reach the provider with exact framing", %{
    jido: jido
  } do
    {mock, context} = mock(List.duplicate(%{reply: {:text, "answer: 24"}}, 6))

    for profile <- [:short, :standard, :long], style <- [:dfs, :bfs] do
      server = start(jido, options(%{profile: profile, search_style: style}))
      assert {:ok, handle} = request(server, context)
      assert {:ok, %{answer: "24"}} = Request.await(handle)
      wire = List.last(MockLLM.report(mock).requests)

      assert wire.body["messages"] == [
               %{"role" => "system", "content" => Method.default_system_prompt(profile, style)},
               %{"role" => "user", "content" => Method.Machine.user_prompt("8 6 4 4")}
             ]

      assert wire.body["temperature"] == 0.0 and wire.body["max_tokens"] == 2048
      refute Map.has_key?(wire.body, "tools")
    end

    assert_script_done(mock)
  end

  test "custom examples and explicit instructions remain exact", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "answer: 24"}}, %{reply: {:text, "answer: 25"}}])
    server = start(jido, options(%{examples: ["  custom example  ", ""]}))
    assert {:ok, handle} = request(server, context)
    assert {:ok, _} = Request.await(handle)
    first = hd(MockLLM.report(mock).requests).body["messages"] |> hd()
    assert first["content"] == Method.default_system_prompt(:short, :dfs, ["custom example"])
    server = start(jido, %{instructions: "Exact prompt"})
    assert {:ok, next} = request(server, context)
    assert {:ok, _} = Request.await(next)

    assert hd(List.last(MockLLM.report(mock).requests).body["messages"])["content"] ==
             "Exact prompt"

    assert_script_done(mock)
  end

  for {text, reason} <- [
        {"found it", :missing_explicit_answer},
        {"no useful branch", :no_solution}
      ] do
    test "#{reason} is a structured failure and a later request succeeds", %{jido: jido} do
      {mock, context} =
        mock([%{reply: {:text, unquote(text)}}, %{reply: {:text, "answer: next"}}])

      server = start(jido)
      assert {:ok, handle} = request(server, context)
      assert {:error, {:failed, reason, result}} = Request.await(handle)
      assert reason == unquote(reason) and result.termination.reason == reason
      assert result.termination.status == :error and result.raw_response == unquote(text)
      assert result.usage.total_tokens == 15
      assert Server.agent(server).state.reply == nil
      assert Method.get_result(Server.agent(server)) == result
      assert List.last(events(handle)).kind == :request_failed
      assert {:ok, next} = request(server, context)
      assert {:ok, %{answer: "next"}} = Request.await(next)
      assert record(server, next).meta.usage.total_tokens == 15
      assert_script_done(mock)
    end
  end

  test "optional explicit answer retains found-solution success without inventing text", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:text, "Trying a promising first operation:\nfound it"}}])
    server = start(jido, options(%{require_explicit_answer: false}))
    assert {:ok, handle} = request(server, context)
    assert {:ok, result} = Request.await(handle)
    assert result.answer == nil and result.found_solution?
    assert result.termination.reason == :success
    assert result.diagnostics.explicit_answer_required == false
    assert_script_done(mock)
  end

  test "public explore helpers retain typed results defaults option precedence and fresh requests",
       %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:text, "answer: 24"}},
        %{reply: {:text, "answer: 25"}},
        %{reply: {:text, "found it"}}
      ])

    server = start_agent(jido, AoT.Public.new!())
    assert {:ok, handle} = AoT.Public.explore(server, "first", context: context)
    assert {:ok, first} = AoT.Public.await(handle)
    assert AoT.Public.answer(first) == "24"

    assert %{last_prompt: "first", last_result: ^first, completed: true} =
             Server.agent(server).state

    assert {:ok, %{answer: "25"}} = AoT.Public.explore_sync(server, "next", context: context)
    assert length(List.last(MockLLM.report(mock).requests).body["messages"]) == 2
    assert AoT.Public.strategy_opts()[:profile] == :standard
    assert AoT.Public.strategy_opts()[:search_style] == :dfs
    custom = start_agent(jido, AoT.Custom.new!())
    assert {:ok, result} = AoT.Custom.explore_sync(custom, "custom", context: context)
    assert result.answer == nil and result.found_solution?
    wire = List.last(MockLLM.report(mock).requests)
    assert wire.body["temperature"] == 0.3 and wire.body["max_tokens"] == 101

    assert hd(wire.body["messages"])["content"] ==
             Method.default_system_prompt(:long, :bfs, ["one example"])

    assert_script_done(mock)
  end

  test "DSL data Builder source JSON and direct Flow keep the AoT result contract", %{jido: jido} do
    {mock, context} = mock(List.duplicate(%{reply: {:text, AoT.puzzle()}}, 5))
    source = AoT.source()
    assert {:ok, definition} = AoT.definition()
    assert AoT.Agent.agent() == definition
    attrs = definition |> Jido.Agent.to_map() |> Map.drop([:id, :state])
    assert {:ok, built} = attrs |> Jido.Agent.Builder.new() |> Jido.Agent.Builder.build()

    registry =
      source
      |> Map.put(:routes, [])
      |> atoms()
      |> Enum.uniq()
      |> Map.new(&{"atoms/#{&1}", {:atom, &1}})
      |> Map.put("models/answer", {:value, source.models.answer.model})

    assert {:ok, document} = Authoring.Codec.encode([source], registry)

    assert {:ok, decoded} =
             Authoring.Codec.decode(AoT.base(), Jason.decode!(Jason.encode!(document)), registry)

    assert decoded == definition and built == definition

    for definition <- [AoT.Agent.agent(), definition, built, decoded] do
      server = start_agent(jido, Jido.Agent.instantiate!(definition))
      assert {:ok, handle} = request(server, context)
      assert {:ok, %{answer: "(4 + (8 - 6)) * 4 = 24"}} = Request.await(handle)
    end

    assert {:ok, profile} = Jido.AI.Profile.new(source)
    assert {:ok, flow} = Authoring.reasoning_flow(profile)

    context =
      Map.merge(context, %{agent_state: %{reply: nil}, jido_ai_profiles: %{assistant: profile}})

    assert {:ok, %{result: result, meta: meta}} =
             Jido.Exec.run(flow, %{query: "8 6 4 4"}, context)

    assert result.backtracking_steps == 3 and meta.model_calls == 1
    assert_script_done(mock)
  end

  test "ordinary Agent turns commit the full AoT result", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, AoT.puzzle()}}])
    server = start(jido, %{requests: %{mode: :turn}})

    assert {:ok, agent} =
             Server.call(
               server,
               Jido.Signal.new!("ai.aot.query", %{query: "8 6 4 4"}, source: "/aot"),
               context: context
             )

    assert agent.state.reply.backtracking_steps == 3
    refute Map.has_key?(agent.state, :requests)
    assert_script_done(mock)
  end

  test "request transforms preserve AoT framing and typed answer repair without provider schema",
       %{
         jido: jido
       } do
    {mock, context} =
      mock([
        %{reply: {:text, "Trying a promising first operation:\nanswer: {\"value\":\"bad\"}"}},
        %{reply: {:text, "Trying another promising first operation:\nanswer: {\"value\":24}"}}
      ])

    context =
      Map.merge(context, %{
        calls: start_supervised!({Elixir.Agent, fn -> 0 end}),
        transform_mode: :headers
      })

    reasoning =
      Map.put(
        AoT.source().reasoning,
        :request_transformer,
        JidoAI.Examples.RequestTransform.Transform
      )

    server =
      start(jido, %{
        reasoning: reasoning,
        result: %{schema: Zoi.object(%{value: Zoi.integer()}), into: :reply, max_repairs: 1}
      })

    assert {:ok, handle} = request(server, context)
    assert {:ok, result} = Request.await(handle)
    assert result.answer == %{value: 24} and result.first_operations_considered == 1
    assert result.usage.total_tokens == 30
    assert record(server, handle).meta.output.status == :repaired
    assert Server.agent(server).state.reply == result

    for {wire, index} <- Enum.with_index(MockLLM.report(mock).requests, 1) do
      assert wire.headers["x-credential-version"] == Integer.to_string(index)
      refute Map.has_key?(wire.body, "response_format")
      refute Map.has_key?(wire.body, "tools")
    end

    assert_script_done(mock)
  end

  test "a typed final answer repairs through the same model Flow and keeps search metadata", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: {:text, "Trying a promising first operation:\nanswer: {\"value\":\"bad\"}"}},
        %{reply: {:text, "Trying another promising first operation:\nanswer: {\"value\":24}"}}
      ])

    server =
      start(jido, %{
        result: %{schema: Zoi.object(%{value: Zoi.integer()}), into: :reply, max_repairs: 1}
      })

    assert {:ok, handle} = request(server, context)
    assert {:ok, result} = Request.await(handle)
    assert result.answer == %{value: 24} and result.first_operations_considered == 1
    assert result.usage.total_tokens == 30
    assert record(server, handle).meta.model_calls == 2
    assert record(server, handle).meta.output.status == :repaired

    assert Enum.map(
             Enum.filter(
               events(handle),
               &(&1.kind in [:output_started, :output_repair, :output_validated])
             ),
             & &1.kind
           ) == [:output_started, :output_repair, :output_validated]

    for wire <- MockLLM.report(mock).requests,
        do: refute(Map.has_key?(wire.body, "response_format"))

    assert_script_done(mock)
  end

  test "configured typed-answer repair retains the AoT envelope without another model call", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:text, "answer: {\"value\":\"bad\"}"}}])

    server =
      start(jido, %{
        result: %{
          schema: Zoi.object(%{value: Zoi.integer()}),
          into: :reply,
          max_repairs: 1,
          repair_fun: &AoT.Repair.repair/4
        }
      })

    assert {:ok, handle} = request(server, context)
    assert {:ok, result} = Request.await(handle)
    assert result.answer == %{value: 24} and result.diagnostics.parser_mode == :repair_callback
    assert record(server, handle).meta.model_calls == 1
    assert_receive {:aot_repair, _, _, _}
    assert_script_done(mock)
  end

  test "typed-answer exhaustion fails without committing the proposed answer", %{jido: jido} do
    {mock, context} = mock(List.duplicate(%{reply: {:text, "answer: {\"value\":\"bad\"}"}}, 2))

    server =
      start(jido, %{
        result: %{schema: Zoi.object(%{value: Zoi.integer()}), into: :reply, max_repairs: 1}
      })

    assert {:ok, handle} = request(server, context)
    assert {:error, {:failed, :error, result}} = Request.await(handle)
    assert result.termination.status == :error
    assert record(server, handle).meta.usage.total_tokens == 30
    assert Server.agent(server).state.reply == nil
    assert_script_done(mock)
  end

  test "AoT output controls see the result envelope and preserve a structured rejection", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:text, AoT.puzzle()}}])
    server = start(jido)
    rejection = %{type: :policy, detail: "rejected"}
    assert {:ok, handle} = request(server, Map.put(context, :reject, rejection))
    assert {:error, {:failed, :error, result}} = Request.await(handle)
    assert result.diagnostics.cause == rejection
    assert_receive {:aot_checked, %{answer: "(4 + (8 - 6)) * 4 = 24"}}
    assert Server.agent(server).state.reply == nil
    assert_script_done(mock)
  end

  test "real provider failures retain their cause and allow the next public exploration", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: {:error, 503, %{error: %{message: "provider down"}}}},
        %{reply: {:text, "answer: next"}}
      ])

    server = start_agent(jido, AoT.Public.new!())
    assert {:ok, handle} = AoT.Public.explore(server, "fail", context: context)
    assert {:error, {:failed, :error, result}} = AoT.Public.await(handle)
    assert is_map(result.diagnostics.cause)
    assert result.diagnostics.error =~ "provider"
    assert Server.agent(server).state.last_result == result
    assert {:ok, %{answer: "next"}} = AoT.Public.explore_sync(server, "next", context: context)
    assert_script_done(mock)
  end

  test "early AoT deltas and typed Signals keep one request and the actual method", %{jido: jido} do
    {mock, context} =
      mock([
        %{
          reply:
            {:stream,
             [%{content: "Trying "}, {:wait, :held}, %{content: "answer: 24\nanswer: 24"}],
             "stop"}
        }
      ])

    server = start(jido)
    assert {:ok, handle} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert Server.agent(server).state.reply == nil
    MockLLM.release(mock, :held)
    assert {:ok, %{answer: "24"}} = Request.await(handle)
    received = events(handle)
    assert Enum.all?(received, &(&1.method == Method.method() and &1.request_id == handle.id))
    assert Enum.map(received, & &1.seq) == Enum.to_list(1..length(received))
    assert Enum.count(received, &(&1.kind == :request_started)) == 1
    assert Enum.count(received, &(&1.kind == :request_completed)) == 1
    typed = delivered(server, handle)
    assert Enum.any?(typed, &(&1.type == "ai.llm.delta" and &1.data.metadata.strategy == :aot))
    assert List.last(typed).data.result.answer == "24"
    assert_script_done(mock)
  end

  test "AoT cancellation keeps its reason stops work and permits a fresh request", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:stream, [{:wait, :held}, %{content: "answer: late"}], "stop"}},
        %{reply: {:text, "answer: next"}}
      ])

    server = start_agent(jido, AoT.Public.new!())
    assert {:ok, handle} = AoT.Public.explore(server, "wait", context: context, stream_to: self())
    assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
    monitor = Process.monitor(provider)
    assert :ok = AoT.Public.cancel(server, request_id: handle.id, reason: :changed_task)
    assert {:error, {:cancelled, :changed_task}} = AoT.Public.await(handle)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert List.last(events(handle)).kind == :request_cancelled
    assert {:ok, %{answer: "next"}} = AoT.Public.explore_sync(server, "next", context: context)
    assert_script_done(mock)
  end

  test "AoT refuses a busy request and rejects tools and invalid method options", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:stream, [{:wait, :held}, %{content: "answer: 24"}], "stop"}}])

    server = start(jido)
    assert {:ok, first} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert {:error, _} = request(server, context, "second")
    assert record(server, first).status == :pending

    for bad <- [
          %{profile: :unknown},
          %{search_style: :unknown},
          %{examples: [1]},
          %{require_explicit_answer: nil},
          %{temperature: 0.3}
        ] do
      assert {:error, _} = AoT.definition(options(bad))
    end

    assert {:error, _} = AoT.definition(%{requests: %{mode: :session, steering: true}})
    assert {:error, _} = AoT.definition(%{tools: [%{target: JidoAI.Examples.RequestScope.Echo}]})
    MockLLM.release(mock, :held)
    assert {:ok, _} = Request.await(first)
    assert_script_done(mock)
  end

  test "an AoT deadline closes held provider work without committing a result", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:stream, [{:wait, :held}, %{content: "answer: late"}], "stop"}}])

    server = start(jido, %{controls: %{AoT.source().controls | timeout: 300}})
    assert {:ok, handle} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
    monitor = Process.monitor(provider)
    assert {:error, reason} = Request.await(handle)
    refute reason == :timeout
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert record(server, handle).status == :failed
    assert Server.agent(server).state.reply == nil
    assert_script_done(mock)
  end

  test "AoT recovery retains method identity and interrupts the old request", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:stream, [{:wait, :held}, %{content: "answer: lost"}], "stop"}},
        %{reply: {:text, "answer: next"}}
      ])

    server = start(jido)
    assert {:ok, handle} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
    monitor = Process.monitor(provider)
    Process.exit(Server.children(server)[{:plugin, Session.Plugin}].pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert {:error, :stream_interrupted} = Request.await(handle)
    assert record(server, handle).method == Method.method()
    assert {:ok, next} = request(server, context)
    assert {:ok, %{answer: "next"}} = Request.await(next)
    assert_script_done(mock)
  end

  test "AoT multimodal queries retain ordered input after the search framing", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "answer: four"}}])
    server = start(jido)

    query = [
      ReqLLM.Message.ContentPart.text("Read the image"),
      ReqLLM.Message.ContentPart.image_url("https://example.test/puzzle.png")
    ]

    assert {:ok, handle} = request(server, context, query)
    assert {:ok, %{answer: "four"}} = Request.await(handle)
    wire = hd(MockLLM.report(mock).requests)
    parts = List.last(wire.body["messages"])["content"]
    assert Enum.map(parts, & &1["type"]) == ["text", "text", "image_url"]
    assert hd(parts)["text"] == Method.Machine.user_prompt("")
    assert record(server, handle).query == query
    assert_script_done(mock)
  end

  test "an unsolicited AoT tool response fails without tool execution or a second model call", %{
    jido: jido
  } do
    {mock, context} =
      mock([%{reply: {:tools, [%{id: "unwanted", name: "echo", arguments: %{value: "unsafe"}}]}}])

    server = start(jido)
    assert {:ok, handle} = request(server, context)
    assert {:error, {:failed, :error, result}} = Request.await(handle)
    assert result.diagnostics.cause == {:unexpected_tool_calls, :algorithm_of_thoughts}
    assert result.usage.total_tokens == 15
    refute Enum.any?(events(handle), &(&1.kind == :tool_started))
    assert_script_done(mock)
  end

  test "blank and incomplete AoT replies retain usage while accepted partial text can finish", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: {:text, ""}},
        %{reply: {:stream, [], "length"}},
        %{reply: {:stream, [%{content: "answer: partial"}], "length"}}
      ])

    server = start(jido)

    for expected <- [:no_solution, :error] do
      assert {:ok, handle} = request(server, context)
      assert {:error, {:failed, reason, result}} = Request.await(handle)
      assert reason == expected
      assert result.usage.total_tokens == 15
      assert record(server, handle).meta.usage == result.usage
      assert Server.agent(server).state.reply == nil

      if expected == :error do
        assert result.raw_response == ""
        assert result.diagnostics.cause == {:incomplete_response, :length}
      end
    end

    assert {:ok, next} = request(server, context)
    assert {:ok, result} = Request.await(next)
    assert result.answer == "partial" and result.raw_response == "answer: partial"
    assert result.usage.total_tokens == 15
    assert_script_done(mock)
  end

  test "AoT telemetry and Signal flags stay separate and known control errors retain their type",
       %{jido: jido} do
    id = "aot_flags_#{System.unique_integer([:positive])}"
    names = for phase <- [:start, :complete, :failed], do: [:jido, :ai, :request, phase]
    :ok = :telemetry.attach_many(id, names, &JidoAI.Examples.Linear.Telemetry.handle/4, self())
    on_exit(fn -> :telemetry.detach(id) end)
    {mock, context} = mock(List.duplicate(%{reply: {:text, "answer: 24"}}, 2))

    for enabled <- [true, false] do
      server = start(jido, %{observability: %{emit_telemetry?: enabled, emit_signals?: false}})

      assert {:ok, handle} =
               request(server, Map.put(context, :reject, %{type: :policy, message: "denied"}))

      assert {:error, {:failed, :error, _}} = Request.await(handle)
      request_id = handle.id

      if enabled do
        assert_receive {:linear_telemetry, [:jido, :ai, :request, :failed], _,
                        %{request_id: ^request_id, strategy: :aot, error_type: :policy}},
                       2_000
      else
        refute_receive {:linear_telemetry, _, _, %{request_id: ^request_id}}, 50
      end

      assert List.last(events(handle)).kind == :request_failed
      assert {:ok, %{status: :disabled}} = Session.delivery_status(server, handle.id)
    end

    refute_receive {:signal, _}, 50
    assert_script_done(mock)
  end

  test "public AoT normalizes legacy examples and temperature while retained helpers remain usable",
       %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "answer: 24"}}])
    server = start_agent(jido, AoT.LegacyValues.new!())
    assert {:ok, result} = AoT.LegacyValues.explore_sync(server, "legacy", context: context)
    wire = hd(MockLLM.report(mock).requests)

    assert hd(wire.body["messages"])["content"] ==
             Method.default_system_prompt(:standard, :dfs, ["example", "24"])

    assert wire.body["temperature"] == 0.0
    adapter = apply(Method, :strategy_module, [])
    assert apply(adapter, :get_result, [Server.agent(server)]) == result
    assert String.starts_with?(Method.generate_call_id(), "aot_")
    assert Method.Machine.from_map(%{}).status == "idle"

    assert Method.Machine.to_map(Method.Machine.from_map(%{status: :completed})).status ==
             :completed

    assert_script_done(mock)
  end

  defp atoms(value) when is_atom(value), do: [value]
  defp atoms(value) when is_list(value), do: Enum.flat_map(value, &atoms/1)
  defp atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> atoms()
  defp atoms(%_{}), do: []

  defp atoms(value) when is_map(value),
    do: value |> Enum.flat_map(fn {k, v} -> atoms(k) ++ atoms(v) end)

  defp atoms(_), do: []
end
