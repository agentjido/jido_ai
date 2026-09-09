defmodule JidoAI.Examples.RetrievalTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.Retrieval, as: Example
  alias Jido.AI.Retrieval.Store
  alias ReqLLM.Message.ContentPart

  setup do
    store = start_supervised!({Store, []})
    {:ok, store: store}
  end

  test "memory routes retain result fields and the complete domain state", %{jido: jido} do
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)

    assert {:ok, agent} =
             Server.call(
               server,
               Example.signal(
                 "retrieval.upsert",
                 %{id: "rain", text: "Tokyo rain forecast", metadata: %{source: "weather"}}
               )
             )

    assert agent.state.result.retrieval.last_upsert.id == "rain"
    assert agent.state.retrieval.namespace == "weather"
    assert agent.state.case_id == "case-7"

    assert {:ok, agent} =
             Server.call(server, Example.signal("retrieval.recall", %{query: "Tokyo rain"}))

    assert %{count: 1, memories: [%{id: "rain", score: score}]} = agent.state.result.retrieval
    assert score > 0
    assert {:ok, agent} = Server.call(server, Example.signal("retrieval.clear", %{}))
    assert agent.state.result.retrieval.cleared == 1
    assert Store.namespace_entries("weather") == []
  end

  test "stored memory reaches an actual Chat tool-loop request", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Take a coat"}}])
    Store.upsert("weather", %{id: "rain", text: "Tokyo rain forecast"})
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)

    assert {:ok, _} =
             Server.call(server, Example.signal("chat.message", %{prompt: "Tokyo weather"}), context: context)

    assert [request] = MockLLM.report(mock).requests
    text = List.last(request.body["messages"])["content"]
    assert text =~ "Relevant memory:" and text =~ "Tokyo rain forecast" and text =~ "User prompt:"
    assert_script_done(mock)
  end

  test "stored memory enriches multimodal input without removing original parts", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Take a coat"}}])
    Store.upsert("weather", %{id: "rain", text: "Tokyo rain forecast"})
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)

    image = ContentPart.image_url("https://example.com/tokyo.png")
    prompt = [ContentPart.text("Tokyo weather"), image]

    assert {:ok, _agent} =
             Server.call(server, Example.signal("case.review", %{query: prompt}), context: context)

    assert [request] = MockLLM.report(mock).requests
    content = List.last(request.body["messages"])["content"]
    assert Enum.at(content, 0)["text"] =~ "Tokyo rain forecast"
    assert Enum.at(content, 1)["text"] == "Tokyo weather"
    assert Enum.at(content, 2)["type"] == "image_url"
    assert_script_done(mock)
  end

  test "a native custom AI route uses its real query with recalled memory", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Take a coat"}}])
    Store.upsert("weather", %{id: "rain", text: "Tokyo rain forecast"})
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)

    assert {:ok, agent} =
             Server.call(
               server,
               Example.signal(
                 "case.review",
                 %{query: "Tokyo weather", prompt: "decoy"}
               ),
               context: context
             )

    assert agent.state.result == "Take a coat"
    assert [request] = MockLLM.report(mock).requests
    text = List.last(request.body["messages"])["content"]
    assert text =~ "Tokyo rain forecast" and text =~ "Tokyo weather"
    refute text =~ "decoy"
    assert_script_done(mock)
  end

  test "the supervised store survives callers and an Agent stop", %{jido: jido, store: store} do
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)

    assert {:ok, _} =
             Server.call(
               server,
               Example.signal("retrieval.upsert", %{id: "kept", text: "Tokyo rain"})
             )

    assert :ok = Server.stop(server, :normal)
    assert Process.alive?(store)
    task = Task.async(fn -> Store.upsert("weather", %{id: "task", text: "Osaka weather"}) end)
    assert %{id: "task"} = Task.await(task)
    server = start_agent(jido, definition)

    assert {:ok, agent} =
             Server.call(server, Example.signal("retrieval.recall", %{query: "weather"}))

    assert agent.state.result.retrieval.count == 2
  end

  test "ranking updates and namespace isolation retain the public Store contract" do
    first =
      Store.upsert("weather", %{
        "id" => "tokyo",
        "text" => "Tokyo rain",
        "metadata" => %{source: 1}
      })

    Store.upsert("weather", %{id: "osaka", text: "Osaka snow"})
    Store.upsert("private", %{id: "tokyo", text: "Tokyo rain"})
    assert [%{id: "tokyo", score: 1.0}] = Store.recall("weather", "TOKYO rain!", top_k: 1)

    updated =
      Store.upsert("weather", %{id: "tokyo", text: "Tokyo rain tomorrow", metadata: %{source: 2}})

    assert updated.inserted_at_ms == first.inserted_at_ms
    assert updated.updated_at_ms >= first.updated_at_ms
    assert updated.metadata == %{source: 2}
    assert [] = Store.recall("weather", "Tokyo rain", min_score: 0.9)
    assert length(Store.recall("weather", "", top_k: 3)) == 2
    assert Store.clear("weather") == 2
    assert [%{id: "tokyo"}] = Store.namespace_entries("private")
  end

  test "unknown string keys cannot prevent normalization or create atoms", %{store: store} do
    unknown = "unknown_memory_#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end

    entry =
      Store.upsert("weather", %{unknown => "ignored", "id" => "kept", "text" => "Tokyo rain"})

    assert entry.id == "kept" and entry.text == "Tokyo rain"
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
    assert_raise Protocol.UndefinedError, fn -> Store.upsert("weather", %{text: self()}) end
    assert Process.alive?(store)
    assert [%{id: "kept"}] = Store.namespace_entries("weather")
  end

  test "direct and Exec Actions accept string keys and current Agent context", %{jido: jido} do
    alias Jido.AI.Actions.Retrieval.{UpsertMemory, RecallMemory, ClearMemory}
    assert {:ok, definition} = Example.definition(namespace: nil)
    server = start_agent(jido, definition)
    agent = Server.agent(server)

    assert {:ok, %{retrieval: %{namespace: namespace}}} =
             UpsertMemory.run(
               %{"id" => "direct", "text" => "Tokyo rain", "metadata" => %{"source" => "manual"}},
               %{agent: agent}
             )

    assert namespace == agent.id

    assert {:ok, %{retrieval: %{count: 1}}} =
             Jido.Exec.run(RecallMemory, %{"query" => "Tokyo", "top_k" => 0}, %{agent: agent})

    assert {:ok, %{retrieval: %{cleared: 1}}} = Jido.Exec.run(ClearMemory, %{}, %{agent: agent})
  end

  test "invalid direct and routed input cannot write to memory", %{jido: jido} do
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)
    before = Server.agent(server).state

    for data <- [
          %{},
          %{text: 42},
          %{text: "Tokyo", metadata: "wrong"},
          %{text: "Tokyo", namespace: 42}
        ] do
      assert {:error, _} = Jido.AI.Actions.Retrieval.UpsertMemory.run(data, %{})
      assert {:error, _} = Server.call(server, Example.signal("retrieval.upsert", data))
    end

    assert Server.agent(server).state == before
    assert Store.namespace_entries("weather") == []
  end

  test "configured limits bound snippets and request opt out keeps routes available", %{
    jido: jido
  } do
    {mock, context} = mock(List.duplicate(%{reply: {:text, "Reviewed"}}, 4))
    Store.upsert("weather", %{id: "rain", text: "Tokyo rain forecast with a long tail"})
    Store.upsert("weather", %{id: "snow", text: "Osaka snow"})
    assert {:ok, definition} = Example.definition(top_k: 1, max_snippet_chars: 5)
    server = start_agent(jido, definition)

    for data <- [
          %{prompt: "Tokyo rain"},
          %{prompt: "Tokyo rain", disable_retrieval: true},
          %{"prompt" => "Tokyo rain", "disable_retrieval" => true}
        ] do
      assert {:ok, _} =
               Server.call(server, Example.signal("chat.message", data), context: context)
    end

    assert {:ok, disabled} = Example.definition(enabled: false)
    disabled_server = start_agent(jido, disabled)

    assert {:ok, _} =
             Server.call(disabled_server, Example.signal("chat.message", %{prompt: "Tokyo rain"}), context: context)

    [enriched | plain] =
      Enum.map(MockLLM.report(mock).requests, &List.last(&1.body["messages"])["content"])

    assert enriched =~ "- Tokyo" and not (enriched =~ "forecast")
    assert plain == List.duplicate("Tokyo rain", 3)

    assert {:ok, agent} =
             Server.call(disabled_server, Example.signal("retrieval.recall", %{query: "Tokyo"}))

    assert agent.state.result.retrieval.count == 2
    assert_script_done(mock)
  end

  test "empty stores and non-enriched Chat routes retain the original request", %{jido: jido} do
    {mock, context} = mock(List.duplicate(%{reply: {:text, "Reviewed"}}, 2))
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)

    assert {:ok, _} =
             Server.call(server, Example.signal("chat.message", %{prompt: "Tokyo rain"}), context: context)

    Store.upsert("weather", %{text: "Tokyo rain"})

    assert {:ok, _} =
             Server.call(server, Example.signal("chat.simple", %{prompt: "Tokyo rain"}), context: context)

    assert Enum.all?(
             MockLLM.report(mock).requests,
             &(List.last(&1.body["messages"])["content"] == "Tokyo rain")
           )

    assert_script_done(mock)
  end

  test "shared named stores and explicit namespace overrides remain independent", %{jido: jido} do
    start_supervised!(Supervisor.child_spec({Store, [name: :alternate_memory]}, id: :alternate))
    assert {:ok, definition} = Example.definition(store: :alternate_memory)
    first = start_agent(jido, definition)
    second = start_agent(jido, definition)

    assert {:ok, _} =
             Server.call(
               first,
               Example.signal("retrieval.upsert", %{id: "shared", text: "Tokyo rain"})
             )

    assert {:ok, agent} =
             Server.call(second, Example.signal("retrieval.recall", %{query: "Tokyo"}))

    assert agent.state.result.retrieval.count == 1
    assert Store.namespace_entries("weather") == []

    assert {:ok, _} =
             Server.call(
               second,
               Example.signal("retrieval.upsert", %{text: "Osaka snow", namespace: "other"})
             )

    assert length(Store.namespace_entries("other", :alternate_memory)) == 1
    assert length(Store.namespace_entries("weather", :alternate_memory)) == 1
  end

  test "a failed Agent result commit does not undo the external memory write", %{jido: jido} do
    assert {:ok, definition} = Example.definition()

    definition = %{
      definition
      | schema:
          Zoi.object(%{
            result: Zoi.string() |> Zoi.default("before"),
            case_id: Zoi.string() |> Zoi.default("case-7")
          })
    }

    server = start_agent(jido, definition)

    assert {:error, _} =
             Server.call(
               server,
               Example.signal("retrieval.upsert", %{id: "written", text: "Tokyo rain"})
             )

    assert Server.agent(server).state.result == "before"
    assert [%{id: "written"}] = Store.namespace_entries("weather")
  end

  test "store restart has an explicit empty lifetime and creates no heir process" do
    supervisor =
      start_supervised!(%{
        id: :memory_owner,
        start: {Supervisor, :start_link, [[{Store, [name: nil]}], [strategy: :one_for_one]]}
      })

    [{Store, store, _, _}] = Supervisor.which_children(supervisor)
    Store.upsert("weather", %{id: "temporary", text: "Tokyo"}, store)
    monitor = Process.monitor(store)
    assert :ok = Supervisor.terminate_child(supervisor, Store)
    assert_receive {:DOWN, ^monitor, :process, ^store, :shutdown}
    assert {:ok, replacement} = Supervisor.restart_child(supervisor, Store)
    assert Store.namespace_entries("weather", replacement) == []
    assert Store.ensure_table!(replacement) == :ok
    assert Process.whereis(:jido_ai_retrieval_store_heir) == nil
  end

  test "store absence fails before model work and opt out still permits a request", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Reviewed"}}])
    assert {:ok, definition} = Example.definition(store: :missing_memory_store)
    server = start_agent(jido, definition)
    before = Server.agent(server).state

    assert {:error, _} =
             Server.call(server, Example.signal("case.review", %{query: "Tokyo"}), context: context)

    assert Server.agent(server).state == before
    assert MockLLM.report(mock).requests == []

    assert {:ok, _} =
             Server.call(
               server,
               Example.signal("case.review", %{query: "Tokyo", disable_retrieval: true}),
               context: context
             )

    assert_script_done(mock)
  end

  test "the Agent DSL reads inserted memory during native AI execution", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Take a coat"}}])
    server = start_agent(jido, Example.Agent.new!())

    assert {:ok, _} =
             Server.call(
               server,
               Example.signal("retrieval.upsert", %{text: "Tokyo rain forecast"})
             )

    assert {:ok, agent} =
             Server.call(server, Example.signal("case.review", %{query: "Tokyo weather"}), context: context)

    assert agent.state.result == "Take a coat"
    assert [request] = MockLLM.report(mock).requests
    assert List.last(request.body["messages"])["content"] =~ "Relevant memory:"
    assert_script_done(mock)
  end

  test "native sessions use enriched queries and preserve memory for later requests", %{
    jido: jido
  } do
    {mock, context} = mock(List.duplicate(%{reply: {:text, "Take a coat"}}, 2))
    Store.upsert("weather", %{id: "rain", text: "Tokyo rain forecast"})
    assert {:ok, definition} = Example.definition(request_mode: :session)
    server = start_agent(jido, definition)

    for id <- ["first", "second"] do
      assert {:ok, _} =
               Server.call(
                 server,
                 Example.signal("case.review", %{query: "Tokyo weather", request_id: id}),
                 context: context
               )

      assert {:ok, %{result: "Take a coat"}} = Jido.AI.Session.await(server, id, 5_000)
    end

    assert Enum.all?(
             MockLLM.report(mock).requests,
             &(List.last(&1.body["messages"])["content"] =~ "Tokyo rain forecast")
           )

    assert [%{id: "rain"}] = Store.namespace_entries("weather")
    assert_script_done(mock)
  end

  test "pure command preparation does not read an external store", %{jido: _jido} do
    {mock, context} = mock([%{reply: {:text, "Reviewed"}}])
    assert {:ok, definition} = Example.definition(store: :missing_memory_store)
    agent = Jido.Agent.instantiate!(definition)

    assert {:ok, candidate, []} =
             Jido.Agent.cmd(agent, Example.signal("case.review", %{query: "Tokyo weather"}), context: context)

    assert candidate.state.result == "Reviewed"
    assert [request] = MockLLM.report(mock).requests
    assert List.last(request.body["messages"])["content"] == "Tokyo weather"
    assert_script_done(mock)
  end

  test "configured store and namespace cannot be replaced by forged caller state", %{jido: jido} do
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)

    context = %{
      retrieval_store: :missing_memory_store,
      plugin_state: %{retrieval: %{namespace: "forged"}},
      agent: %{id: "forged"},
      state: %{retrieval: %{namespace: "forged"}},
      jido_ai_retrieval_capability: %{
        action: Jido.AI.Actions.Retrieval.ClearMemory,
        into: :case_id
      }
    }

    assert {:ok, agent} =
             Server.call(
               server,
               Example.signal(
                 "retrieval.upsert",
                 %{id: "bound", text: "Tokyo", into: :case_id}
               ),
               context: context
             )

    assert agent.state.result.retrieval.namespace == "weather"
    assert agent.state.case_id == "case-7"
    assert [%{id: "bound"}] = Store.namespace_entries("weather")
    assert Store.namespace_entries("forged") == []
  end

  test "invalid Plugin options fail and empty restored config retains declared values" do
    for opts <- [
          [enabled: :invalid],
          [namespace: 12],
          [top_k: "two"],
          [max_snippet_chars: 0],
          [store: self()],
          [into: nil],
          [unknown: true],
          [top_k: 1, top_k: 2]
        ] do
      assert {:error, _} = Example.definition(opts)
    end

    {:retrieval, schema} =
      Jido.AI.Plugins.Retrieval.Agent.state_spec(
        enabled: false,
        namespace: "saved",
        top_k: 5,
        max_snippet_chars: 20
      )

    assert {:ok, %{enabled: false, namespace: "saved", top_k: 5, max_snippet_chars: 20}} =
             Zoi.parse(schema, %{})
  end

  test "a model calls the real memory Action and receives its stored result", %{jido: jido} do
    {mock, context} =
      mock([
        %{
          reply: {:tools, [%{id: "memory-call", name: "recall_memory", arguments: %{query: "Tokyo"}}]}
        },
        %{reply: {:text, "Take a coat"}}
      ])

    Store.upsert("weather", %{id: "rain", text: "Tokyo rain forecast"})
    server = start_agent(jido, Example.Agent.new!())

    assert {:ok, agent} =
             Server.call(
               server,
               Example.signal(
                 "case.review",
                 %{query: "Tokyo weather", disable_retrieval: true}
               ),
               context: context
             )

    assert agent.state.result == "Take a coat"
    [_, followup] = MockLLM.report(mock).requests
    result = followup.body["messages"] |> Enum.find(&(&1["role"] == "tool"))
    assert result["tool_call_id"] == "memory-call"

    assert %{
             "ok" => true,
             "result" => %{
               "retrieval" => %{
                 "namespace" => "weather",
                 "count" => 1,
                 "memories" => [%{"id" => "rain"}]
               }
             }
           } = Jason.decode!(result["content"])

    assert_script_done(mock)
  end

  test "an Agent checkpoint keeps config but does not copy the external memory store", %{
    jido: jido
  } do
    Store.upsert("weather", %{id: "external", text: "Tokyo rain"})
    server = start_agent(jido, Example.Agent.new!())
    assert {:ok, checkpoint} = Jido.Agent.checkpoint(Server.agent(server))
    assert checkpoint.state.result == nil

    assert Map.keys(checkpoint.state.retrieval) |> Enum.sort() == [
             :enabled,
             :max_snippet_chars,
             :namespace,
             :top_k
           ]

    assert :ok = Server.stop(server, :normal)
    assert {:ok, restored} = Jido.Agent.restore(Example.Agent, checkpoint)
    server = start_agent(jido, restored)

    assert {:ok, agent} =
             Server.call(server, Example.signal("retrieval.recall", %{query: "Tokyo"}))

    assert agent.state.result.retrieval.count == 1
    assert Store.clear("weather") == 1
    assert {:ok, restored_again} = Jido.Agent.restore(Example.Agent, checkpoint)
    another = start_agent(jido, %{restored_again | id: "another-restored"})

    assert {:ok, agent} =
             Server.call(another, Example.signal("retrieval.recall", %{query: "Tokyo"}))

    assert agent.state.result.retrieval.count == 0
  end
end
