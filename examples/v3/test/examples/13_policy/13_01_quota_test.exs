defmodule JidoAI.Examples.QuotaTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.Quota, as: Example
  alias Jido.AI.Quota.Store

  setup do
    start_supervised!({Store, []})
    :ok
  end

  test "usage Signals count once and retain total-token precedence", %{jido: jido} do
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)
    data = %{call_id: "observed", total_tokens: 12, input_tokens: 90, output_tokens: 90}
    assert {:ok, _} = Server.call(server, Example.signal("ai.usage", data))
    assert {:ok, _} = Server.call(server, Example.signal("ai.usage", data))
    assert {:ok, agent} = Server.call(server, Example.signal("quota.status", %{}))
    assert agent.state.result.quota.usage.requests == 1
    assert agent.state.result.quota.usage.total_tokens == 12
    assert agent.state.case_id == "case-13"
  end

  test "over-budget requests fail before HTTP and reset permits later work", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Reviewed"}}])
    Store.add_usage("team", 20, 60_000)
    assert {:ok, definition} = Example.definition(max_total_tokens: 20)
    server = start_agent(jido, definition)

    assert {:error, error} =
             Server.call(
               server,
               Example.signal("chat.simple", %{prompt: "Review", request_id: "blocked"}),
               context: context
             )

    assert Jido.AI.Error.normalize(error).type == :quota_exceeded
    assert MockLLM.report(mock).requests == []
    assert {:ok, agent} = Server.call(server, Example.signal("quota.reset", %{}))
    assert agent.state.result.quota == %{scope: "team", reset: true}

    assert {:ok, _} =
             Server.call(server, Example.signal("chat.simple", %{prompt: "Review"}),
               context: context
             )

    assert_script_done(mock)
  end

  for mode <- [:turn, :session] do
    test "native #{mode} requests record actual model usage", %{jido: jido} do
      {mock, context} = mock([%{reply: {:text, "Reviewed"}}])
      assert {:ok, definition} = Example.definition(mode: unquote(mode))
      server = start_agent(jido, definition)

      assert {:ok, _} =
               Server.call(
                 server,
                 Example.signal("case.review", %{query: "Review", request_id: "observed"}),
                 context: context
               )

      await(unquote(mode), server, "observed")
      assert %{requests: 1, total_tokens: 15} = Store.get("team")
      assert [%{status: :complete, total_tokens: 15}] = Store.ledger("team")
      assert_script_done(mock)
    end
  end

  test "string fallback keys invalid tokens and distinct calls in one request are handled", %{
    jido: jido
  } do
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)

    for data <- [
          %{"call_id" => "a", "request_id" => "same", "input_tokens" => 7, "output_tokens" => 5},
          %{call_id: "b", request_id: "same", input_tokens: -2, output_tokens: "invalid"},
          %{call_id: "c", total_tokens: 0, input_tokens: 10},
          %{call_id: "a", total_tokens: 99}
        ] do
      assert {:ok, _} = Server.call(server, Example.signal("ai.usage", data))
    end

    assert %{requests: 3, total_tokens: 12} = Store.get("team")
  end

  test "a completed model remains charged after output validation fails", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Rejected answer"}}])

    assert {:ok, definition} =
             Example.definition(profile: %{controls: %{timeout: 5_000, output: [Example.Reject]}})

    server = start_agent(jido, definition)

    assert {:error, _} =
             Server.call(server, Example.signal("case.review", %{query: "Review"}),
               context: context
             )

    assert Server.agent(server).state.result == nil
    assert %{requests: 1, total_tokens: 15} = Store.get("team")
    assert [%{status: :complete}] = Store.ledger("team")
    assert_script_done(mock)
  end

  test "invalid structured Action output retains completed model cost", %{jido: jido} do
    {mock, context} = mock([%{reply: {:object, %{label: 42}}}])
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)

    assert {:error, _} =
             Server.call(
               server,
               Example.signal(
                 "chat.generate_object",
                 %{prompt: "Label", object_schema: Zoi.object(%{label: Zoi.string()})}
               ),
               context: context
             )

    assert Server.agent(server).state.result == nil
    assert %{requests: 1, total_tokens: 15} = Store.get("team")
    assert_script_done(mock)
  end

  test "failed provider invocations retain unknown usage and consume a request slot", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:error, 503, "Unavailable"}}])
    assert {:ok, definition} = Example.definition(max_requests: 1)
    server = start_agent(jido, definition)

    assert {:error, _} =
             Server.call(server, Example.signal("chat.simple", %{prompt: "Review"}),
               context: context
             )

    assert %{requests: 1, total_tokens: 0} = Store.get("team")
    assert [%{status: :unknown, total_tokens: nil}] = Store.ledger("team")
    assert %{accounting: %{unknown_calls: 1}} = Store.status("team", %{}, 60_000)

    assert {:error, %{type: :quota_exceeded}} =
             Server.call(server, Example.signal("chat.simple", %{prompt: "Again"}),
               context: context
             )

    assert_script_done(mock)
  end

  test "repair calls share one request and token budget", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:object, %{label: 42}}}, %{reply: {:object, %{label: "ready"}}}])

    result = %{schema: Zoi.object(%{label: Zoi.string()}), into: :result, max_repairs: 1}
    assert {:ok, definition} = Example.definition(max_requests: 2, profile: %{result: result})
    server = start_agent(jido, definition)

    assert {:ok, agent} =
             Server.call(server, Example.signal("case.review", %{query: "Label"}),
               context: context
             )

    assert agent.state.result == %{label: "ready"}
    assert %{requests: 2, total_tokens: 30} = Store.get("team")

    assert {:error, %{type: :quota_exceeded}} =
             Server.call(server, Example.signal("case.review", %{query: "Again"}),
               context: context
             )

    assert_script_done(mock)
  end

  test "the next model call is blocked when a tool round reaches the token budget", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:tools, [%{id: "echo", name: "echo", arguments: %{text: "Reviewed"}}]}}])

    assert {:ok, definition} =
             Example.definition(
               max_total_tokens: 15,
               profile: %{tools: [%{name: "echo", target: Example.Echo}]}
             )

    server = start_agent(jido, definition)

    assert {:error, _} =
             Server.call(server, Example.signal("case.review", %{query: "Review"}),
               context: context
             )

    assert Server.agent(server).state.result == nil
    assert %{requests: 1, total_tokens: 15} = Store.get("team")
    assert_script_done(mock)
  end

  test "a nested callable reasoning tool uses the same quota scope", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "reason", name: "reason", arguments: %{prompt: "Think"}}]}},
        %{reply: {:text, "Conclusion: Reviewed"}},
        %{reply: {:text, "Reviewed"}}
      ])

    assert {:ok, definition} =
             Example.definition(
               max_requests: 3,
               profile: %{
                 tools: [
                   %{
                     name: "reason",
                     target: Example.ReasoningFlow,
                     forward_context: [:default_model, :model_options, :ai, :jido]
                   }
                 ]
               }
             )

    server = start_agent(jido, definition)
    context = Map.put(context, :default_model, MockLLM.model())

    assert {:ok, agent} =
             Server.call(server, Example.signal("case.review", %{query: "Review"}),
               context: context
             )

    assert agent.state.result == "Reviewed"
    assert %{requests: 3, total_tokens: 45} = Store.get("team")
    assert length(Store.ledger("team")) == 3
    assert_script_done(mock)
  end

  test "concurrent Agents cannot both spend the last request slot", %{jido: jido} do
    {mock, context} = mock([%{reply: {:wait, :last_slot, {:text, "Reviewed"}}}])
    assert {:ok, definition} = Example.definition(max_requests: 1)
    first = start_agent(jido, definition)
    second = start_agent(jido, definition)

    task =
      Task.async(fn ->
        Server.call(first, Example.signal("case.review", %{query: "Review"}), context: context)
      end)

    assert_receive {:mock_llm_waiting, ^mock, :last_slot, _}, 2_000

    assert {:error, %{type: :quota_exceeded}} =
             Server.call(second, Example.signal("case.review", %{query: "Review"}),
               context: context
             )

    assert %{requests: 1, total_tokens: 0} = Store.get("team")
    assert :ok = MockLLM.release(mock, :last_slot)
    assert {:ok, _} = Task.await(task, 5_000)
    assert %{requests: 1, total_tokens: 15} = Store.get("team")
    assert_script_done(mock)
  end

  test "a mirrored model usage Signal cannot charge the provider call twice", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Reviewed"}}])
    assert {:ok, definition} = Example.definition(mode: :session)
    server = start_agent(jido, definition)

    assert {:ok, _} =
             Server.call(
               server,
               Example.signal("case.review", %{query: "Review", request_id: "mirror"}),
               context: context
             )

    await(:session, server, "mirror")
    assert [%{id: id}] = Store.ledger("team")

    for tokens <- [15, 99] do
      assert {:ok, _} =
               Server.call(
                 server,
                 Example.signal("ai.usage", %{call_id: id, total_tokens: tokens})
               )
    end

    assert %{requests: 1, total_tokens: 15} = Store.get("team")
    assert_script_done(mock)
  end

  test "stream cancellation preserves observed usage and marks the remaining cost unknown", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{
          reply:
            {:stream,
             [
               %{content: "Partial"},
               {:usage, %{prompt_tokens: 3, completion_tokens: 2, total_tokens: 5}},
               {:wait, :partial_usage}
             ]}
        }
      ])

    profile = %{requests: %{mode: :session, streaming: true}}
    assert {:ok, definition} = Example.definition(profile: profile)
    server = start_agent(jido, definition)

    assert {:ok, _} =
             Server.call(
               server,
               Example.signal("case.review", %{query: "Review", request_id: "cancel"}),
               context: context
             )

    assert_receive {:mock_llm_waiting, ^mock, :partial_usage, provider}, 2_000
    assert_eventually(fn -> Store.get("team").total_tokens == 5 end)
    monitor = Process.monitor(provider)
    assert :ok = Jido.AI.Session.cancel(Jido.AI.Request.Handle.new("cancel", server, "Review"))
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert_eventually(fn -> match?([%{status: :unknown}], Store.ledger("team")) end)
    assert %{requests: 1, total_tokens: 5} = Store.get("team")
    assert [%{id: id}] = Store.ledger("team")
    assert %{requests: 1, total_tokens: 8} = Store.record_usage("team", id, 8, 60_000)
    assert %{requests: 1, total_tokens: 8} = Store.record_usage("team", id, 8, 60_000)
    assert_script_done(mock)
  end

  test "the Agent DSL shares one budget across AI status and reset routes", %{jido: jido} do
    {mock, context} = mock(List.duplicate(%{reply: {:text, "Reviewed"}}, 2))
    server = start_agent(jido, Example.Agent.new!())

    assert {:ok, agent} =
             Server.call(server, Example.signal("case.review", %{query: "Review"}),
               context: context
             )

    assert agent.state.result == "Reviewed" and agent.state.case_id == "case-13"

    assert {:error, %{type: :quota_exceeded}} =
             Server.call(server, Example.signal("case.review", %{query: "Again"}),
               context: context
             )

    assert {:ok, agent} = Server.call(server, Example.signal("quota.status", %{}))
    assert agent.state.result.quota.usage.requests == 1
    assert {:ok, _} = Server.call(server, Example.signal("quota.reset", %{}))

    assert {:ok, _} =
             Server.call(server, Example.signal("case.review", %{query: "Again"}),
               context: context
             )

    assert %{requests: 1, total_tokens: 15} = Store.get("dsl")
    assert_script_done(mock)
  end

  test "stream usage snapshots and the final response charge only the cumulative total", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{
          reply:
            {:stream,
             [
               %{content: "Reviewed"},
               {:usage, %{prompt_tokens: 3, completion_tokens: 2, total_tokens: 5}},
               {:usage, %{prompt_tokens: 3, completion_tokens: 2, total_tokens: 5}},
               {:usage, %{prompt_tokens: 2, completion_tokens: 1, total_tokens: 3}}
             ]}
        }
      ])

    assert {:ok, definition} = Example.definition(profile: %{requests: %{streaming: true}})
    server = start_agent(jido, definition)

    assert {:ok, agent} =
             Server.call(server, Example.signal("case.review", %{query: "Review"}),
               context: context
             )

    assert agent.state.result == "Reviewed"
    assert %{requests: 1, total_tokens: 15} = Store.get("team")
    assert [%{status: :complete, total_tokens: 15}] = Store.ledger("team")
    assert_script_done(mock)
  end

  test "a stream disconnect preserves partial usage without a successful Agent commit", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{
          reply:
            {:stream,
             [
               %{content: "Partial"},
               {:usage, %{prompt_tokens: 3, completion_tokens: 2, total_tokens: 5}},
               :disconnect
             ]}
        }
      ])

    assert {:ok, definition} = Example.definition(profile: %{requests: %{streaming: true}})
    server = start_agent(jido, definition)

    assert {:error, _} =
             Server.call(server, Example.signal("case.review", %{query: "Review"}),
               context: context
             )

    assert Server.agent(server).state.result == nil
    assert %{requests: 1, total_tokens: 5} = Store.get("team")
    assert [%{status: :unknown, total_tokens: 5}] = Store.ledger("team")
    assert_script_done(mock)
  end

  test "a held call cannot charge a replacement window after reset", %{jido: jido} do
    {mock, context} = mock([%{reply: {:wait, :reset_window, {:text, "Reviewed"}}}])
    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)

    task =
      Task.async(fn ->
        Server.call(server, Example.signal("case.review", %{query: "Review"}), context: context)
      end)

    assert_receive {:mock_llm_waiting, ^mock, :reset_window, _}, 2_000
    assert :ok = Store.reset("team")
    assert :ok = MockLLM.release(mock, :reset_window)
    assert {:ok, _} = Task.await(task, 5_000)
    assert %{requests: 0, total_tokens: 0} = Store.get("team")
    assert [] = Store.ledger("team")
    assert_script_done(mock)
  end

  test "expiry starts a new generation and ignores late completion from the old one" do
    clock = start_supervised!({Agent, fn -> 1_000 end})

    store =
      start_supervised!(
        Supervisor.child_spec({Store, name: nil, clock: fn -> Agent.get(clock, & &1) end},
          id: :clocked_quota
        )
      )

    binding = %{
      store: store,
      scope: "clocked",
      window_ms: 100,
      enabled: true,
      max_requests: 1,
      max_total_tokens: nil
    }

    assert {:ok, old} = Store.begin_call(binding, "old")
    Agent.update(clock, fn _ -> 1_100 end)
    assert %{usage: %{requests: 0}} = Store.status("clocked", binding, 100, store)
    assert {:ok, new} = Store.begin_call(binding, "new")
    assert :ok = Store.progress(store, old, 5)
    assert :ok = Store.finish_call(store, old, 15)
    assert :ok = Store.finish_call(store, new, 7)
    assert :ok = Store.finish_call(store, new, 70)

    assert %{requests: 1, total_tokens: 7, window_started_at_ms: 1_100} =
             Store.get("clocked", store)

    assert [%{id: "new", status: :complete}] = Store.ledger("clocked", store)
  end

  test "legacy rows import atomically and retain counters without inventing call records" do
    now = System.system_time(:millisecond)

    assert :ok =
             Store.import_rows([
               {"tuple", now, 3, 12},
               {"map", %{"window_started_at_ms" => now, "requests" => 2, "total_tokens" => 9}}
             ])

    assert %{requests: 3, total_tokens: 12} = Store.get("tuple")
    assert %{accounting: %{unattributed_calls: 3}} = Store.status("tuple", %{}, 60_000)
    assert [] = Store.ledger("tuple")
    assert %{requests: 3, total_tokens: 13} = Store.add_usage("map", 4, 60_000)
    assert {:error, :scope_exists} = Store.import_rows([{"new", now, 1, 1}, {"tuple", now, 0, 0}])

    assert {:error, :invalid_quota_row} =
             Store.import_rows([{"new", now, 1, 1}, {"bad", now, -1, 0}])

    assert {:error, :duplicate_scope} =
             Store.import_rows([{"new", now, 1, 1}, {"new", now, 1, 1}])

    assert %{requests: 0} = Store.get("new")
    assert %{requests: 3, total_tokens: 12} = Store.get("tuple")
  end

  test "disabled enforcement and unbudgeted embedding calls still record usage", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Reviewed"}}, %{reply: {:embeddings, [[0.1, 0.2]]}}])
    assert {:ok, disabled} = Example.definition(enabled: false, max_requests: 0)
    server = start_agent(jido, disabled)

    assert {:ok, _} =
             Server.call(server, Example.signal("case.review", %{query: "Review"}),
               context: context
             )

    assert {:ok, enabled} = Example.definition(max_requests: 0)
    server = start_agent(jido, enabled)

    assert {:ok, _} =
             Server.call(
               server,
               Example.signal("chat.embed", %{
                 texts: "Review",
                 model: "openai:text-embedding-3-small"
               }),
               context: %{context | model_options: MockLLM.options(mock, :embedding)}
             )

    assert {:ok, _} = Server.call(server, Example.signal("case.note", %{}))
    assert %{requests: 2, total_tokens: 20} = Store.get("team")
    assert_script_done(mock)
  end

  test "pure Agent commands enforce the same provider budget and reject forged context" do
    {mock, context} = mock([%{reply: {:text, "Reviewed"}}])
    assert {:ok, definition} = Example.definition(max_requests: 1)
    agent = Jido.Agent.instantiate!(definition)

    context =
      Map.merge(context, %{
        quota_store: :missing_store,
        jido_ai_quota: %{enabled: false},
        jido_ai_quota_call_id: "forged"
      })

    assert {:ok, agent, _} =
             Jido.Agent.cmd(agent, Example.signal("case.review", %{query: "Review"}),
               context: context
             )

    assert agent.state.result == "Reviewed"

    assert {:error, _} =
             Jido.Agent.cmd(agent, Example.signal("case.review", %{query: "Again"}),
               context: context
             )

    assert [%{id: id}] = Store.ledger("team")
    refute id == "forged"
    assert_script_done(mock)
  end

  test "a nested reasoning tool cannot bypass the outer model budget", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:tools, [%{id: "reason", name: "reason", arguments: %{prompt: "Think"}}]}}])

    assert {:ok, definition} =
             Example.definition(
               max_requests: 1,
               profile: %{
                 tools: [
                   %{
                     name: "reason",
                     target: Example.ReasoningFlow,
                     forward_context: [:default_model, :model_options, :ai, :jido]
                   }
                 ]
               }
             )

    server = start_agent(jido, definition)
    context = Map.put(context, :default_model, MockLLM.model())

    assert {:error, _} =
             Server.call(server, Example.signal("case.review", %{query: "Review"}),
               context: context
             )

    assert %{requests: 1, total_tokens: 15} = Store.get("team")
    assert Server.agent(server).state.result == nil
    assert_script_done(mock)
  end

  test "owner termination keeps observed tokens and makes unfinished usage explicit" do
    parent = self()
    binding = %{store: Store, scope: "owner", window_ms: 60_000, enabled: false}

    pid =
      spawn(fn ->
        Jido.AI.Quota.track(%{jido_ai_quota: binding}, fn progress ->
          progress.(%{input_tokens: 3, output_tokens: 2})
          send(parent, :usage_observed)

          receive do
            :finish -> {:ok, %{usage: %{total_tokens: 8}}}
          end
        end)
      end)

    assert_receive :usage_observed
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    assert_eventually(fn -> match?([%{status: :unknown}], Store.ledger("owner")) end)
    assert %{requests: 1, total_tokens: 5} = Store.get("owner")
  end

  test "missing provider usage does not become a known zero cost", %{jido: jido} do
    {mock, context} =
      mock([
        %{
          reply:
            {:raw,
             %{
               id: "missing-usage",
               object: "chat.completion",
               model: "gpt-4o-mini",
               choices: [
                 %{
                   index: 0,
                   message: %{role: "assistant", content: "Reviewed"},
                   finish_reason: "stop"
                 }
               ]
             }}
        }
      ])

    assert {:ok, definition} = Example.definition()
    server = start_agent(jido, definition)

    assert {:ok, _} =
             Server.call(server, Example.signal("case.review", %{query: "Review"}),
               context: context
             )

    assert %{requests: 1, total_tokens: 0} = Store.get("team")
    assert [%{status: :unknown, total_tokens: nil}] = Store.ledger("team")
    assert_script_done(mock)
  end

  test "HTTP retries share one guarded invocation and use only reported tokens", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:error, 429, "Rate limited"}}, %{reply: {:text, "Reviewed"}}])

    options =
      MockLLM.options(mock)
      |> Keyword.put(:max_retries, 1)
      |> Keyword.update!(:req_http_options, &Keyword.delete(&1, :retry))

    context = %{context | model_options: options, ai: %{assistant: %{options: options}}}
    assert {:ok, definition} = Example.definition(max_requests: 1)
    server = start_agent(jido, definition)

    assert {:ok, _} =
             Server.call(server, Example.signal("case.review", %{query: "Review"}),
               context: context
             )

    assert length(MockLLM.report(mock).requests) == 2
    assert %{requests: 1, total_tokens: 15} = Store.get("team")
    assert [%{status: :complete}] = Store.ledger("team")
    assert_script_done(mock)
  end

  test "an explicit Store and status result field retain committed policy defaults", %{jido: jido} do
    store =
      start_supervised!(
        Supervisor.child_spec({Store, name: :quota_example_alternate}, id: :alternate)
      )

    assert {:ok, definition} =
             Example.definition(
               store: :quota_example_alternate,
               scope: nil,
               into: :quota_result,
               max_requests: 3
             )

    definition = %{
      definition
      | schema:
          Zoi.object(%{
            result: Zoi.any() |> Zoi.default(nil),
            quota_result: Zoi.any() |> Zoi.default(nil),
            case_id: Zoi.string() |> Zoi.default("case-13")
          })
    }

    server = start_agent(jido, definition)
    id = Server.agent(server).id
    Store.add_usage(id, 12, 60_000, store)

    context = %{
      quota_store: Store,
      state: %{quota: %{scope: "forged"}},
      plugin_state: %{quota: %{max_requests: 99}},
      jido_ai_quota_capability: %{action: Jido.AI.Actions.Quota.Reset}
    }

    assert {:ok, agent} =
             Server.call(server, Example.signal("quota.status", %{}), context: context)

    assert agent.state.result == nil

    assert %{scope: ^id, usage: %{requests: 1, total_tokens: 12}, limits: %{max_requests: 3}} =
             agent.state.quota_result.quota

    assert {:ok, %{quota: %{usage: %{total_tokens: 12}}}} =
             Jido.Exec.run(Jido.AI.Actions.Quota.GetStatus, %{"scope" => id}, %{
               quota_store: store
             })

    assert %{requests: 0} = Store.get(id)
    assert :ok = Server.stop(server, :normal)
    assert Process.alive?(store)
    assert %{requests: 1, total_tokens: 12} = Store.get(id, store)
  end

  test "missing Store fails before provider use and a Store restart starts empty", %{jido: jido} do
    {mock, context} = mock([])
    assert {:ok, definition} = Example.definition(store: :missing_quota_store)
    server = start_agent(jido, definition)

    assert {:error, _} =
             Server.call(server, Example.signal("case.review", %{query: "Review"}),
               context: context
             )

    Store.add_usage("team", 15, 60_000)
    stop_supervised!(Store)
    start_supervised!({Store, []})
    assert %{requests: 0, total_tokens: 0} = Store.get("team")
    assert_script_done(mock)
  end

  defp assert_eventually(fun, attempts \\ 100)

  defp assert_eventually(fun, 0),
    do: assert(fun.(), "Quota ledger: #{inspect(Store.ledger("team"))}")

  defp assert_eventually(fun, attempts) do
    unless fun.() do
      Process.sleep(10)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp await(:turn, _, _), do: :ok

  defp await(:session, server, id) do
    assert {:ok, _} = Jido.AI.Session.await(server, id, 5_000)
    :ok
  end
end
