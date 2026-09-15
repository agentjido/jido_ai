defmodule JidoAI.Examples.SteeringTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Request, Orchestration}
  alias JidoAI.Examples.Steering.Agent
  alias JidoAI.Examples.Session.Agent, as: API

  defp texts(server) do
    conversation(Server.agent(server))
    |> Enum.filter(&(&1.role == :user))
    |> Enum.map(&Jido.AI.Query.summarize(&1.content))
  end

  defp start(jido, changes \\ %{}) do
    definition = Agent.definition()
    profile = Jido.AI.Agent.profile(Agent, :assistant) |> Map.from_struct()

    profile = %{
      profile
      | controls: Map.put(profile.controls, :input, [JidoAI.Examples.Steering.ObserveQueue]),
        tools: [
          %{name: "wait", target: JidoAI.Examples.AIRuntime.WaitTool, forward_context: [:observer], timeout: 8_000}
        ]
    }

    profile = Map.merge(profile, changes)

    {:ok, definition} =
      Jido.AI.Authoring.lower(
        %{
          name: "steering_case",
          schema: definition.schema,
          routes: [{"ai.ask", Jido.AI.Authoring.ai(:assistant)}]
        },
        [profile]
      )

    start_agent(jido, Jido.Agent.instantiate!(definition))
  end

  @tag history_case: "HIST-21/same-request"
  test "steer and inject during a real tool keep one handle, FIFO input and committed consumption",
       %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "held", name: "wait", arguments: %{n: 7}}]}},
        %{reply: {:text, "Updated answer"}},
        %{reply: {:text, "History retained"}}
      ])

    server = start(jido)
    {:ok, request, events} = API.ask_stream(server, "Review the code", context: context)
    id = request.id
    assert_receive {:tool_waiting, tool, 7}, 2_000
    assert texts(server) == ["Review the code"]

    assert {:ok, %{status: :queued, request_id: ^id, input_id: first_id}} =
             Orchestration.steer(request, "  Focus on auth.  ",
               extra_refs: %{request_id: "caller-ref", custom: 1},
               source: "/human"
             )

    assert {:ok, %{status: :queued, input_id: second_id}} =
             Orchestration.inject(server, "Include expired tokens.", source: "/peer")

    assert texts(server) == ["Review the code"]
    send(tool, :release)
    assert {:ok, "Updated answer"} = Request.await(request)
    events = Enum.to_list(events)
    consumed = Enum.filter(events, &(&1.kind == :input_injected))
    assert Enum.map(consumed, & &1.data.input_id) == [first_id, second_id]
    assert Enum.all?(consumed, &(&1.request_id == id))
    assert Enum.count(events, &(&1.kind == :request_completed)) == 1
    assert texts(server) == ["Review the code", "Focus on auth.", "Include expired tokens."]
    entries = conversation(Server.agent(server))

    assert Enum.find(entries, &(Jido.AI.Query.summarize(&1.content) == "Focus on auth.")).refs == %{
             request_id: id,
             run_id: hd(events).run_id,
             custom: 1,
             source: "/human",
             context_ref: "default"
           }

    [_, wire] = MockLLM.report(mock).requests
    users = Enum.filter(wire.body["messages"], &(&1["role"] == "user"))
    assert Enum.map(users, & &1["content"]) == texts(server)
    tool_result = Enum.find(wire.body["messages"], &(&1["role"] == "tool"))
    assert Jason.decode!(tool_result["content"]) == %{"ok" => true, "result" => %{"value" => 7}}
    {:ok, next} = API.ask(server, "Follow up", context: context)
    assert {:ok, "History retained"} = Request.await(next)
    next_wire = List.last(MockLLM.report(mock).requests)
    assert Enum.count(next_wire.body["messages"], &(&1["role"] == "tool")) == 1
    assistant = Enum.find(next_wire.body["messages"], &is_list(&1["tool_calls"]))
    assert hd(assistant["tool_calls"])["id"] == "held"
    assert_script_done(mock)
  end

  @tag history_case: "HIST-21/final-closure"
  test "input accepted during a held final response forces another model round", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:wait, :first, {:text, "Initial answer"}}},
        %{reply: {:text, "Revised answer"}}
      ])

    server = start(jido)
    {:ok, request, events} = API.ask_stream(server, "Report", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :first, _}, 2_000
    assert {:ok, %{status: :queued}} = Orchestration.steer(request, "Add the missing case.")
    MockLLM.release(mock, :first)
    assert {:ok, "Revised answer"} = Request.await(request)
    events = Enum.to_list(events)
    assert Enum.count(events, &(&1.kind == :llm_completed)) == 2
    assert Enum.count(events, &(&1.kind == :request_completed)) == 1
    assert texts(server) == ["Report", "Add the missing case."]
    assert_script_done(mock)
  end

  test "an empty seal rejects late input while output control remains blocked", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Sealed"}}])

    controls = %{
      output: [JidoAI.Examples.AIRuntime.WaitControl],
      input: [JidoAI.Examples.Steering.ObserveQueue],
      timeout: 10_000
    }

    server = start(jido, %{controls: controls})
    {:ok, request} = API.ask(server, "Report", context: context)
    assert_receive {:control_waiting, control}, 2_000
    assert {:error, %{status: :rejected, reason: :closed}} = Orchestration.steer(request, "Too late")
    assert texts(server) == ["Report"]
    send(control, :release)
    assert {:ok, "Sealed"} = Request.await(request)
    assert_script_done(mock)
  end

  test "idle, stale IDs and blank content reject without history changes", %{jido: jido} do
    {mock, context} = mock([%{reply: {:wait, :held, {:text, "Done"}}}])
    server = start(jido)
    assert {:error, %{reason: :idle}} = Orchestration.steer(server, "Idle")
    assert {:error, :invalid_content} = Orchestration.inject(server, [:invalid])
    {:ok, request} = API.ask(server, "Report", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000

    assert {:error, %{reason: :request_mismatch}} =
             Orchestration.steer(server, "Wrong request", expected_request_id: "stale")

    assert {:error, %{reason: :empty_content}} = Orchestration.steer(request, " \n ")
    assert texts(server) == ["Report"]
    MockLLM.release(mock, :held)
    assert {:ok, "Done"} = Request.await(request)
    assert_script_done(mock)
  end

  test "the default queue admits 64 inputs and keeps FIFO order", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:wait, :held, {:text, "First"}}}, %{reply: {:text, "After inputs"}}])

    server = start(jido)
    {:ok, request} = API.ask(server, "Report", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    for n <- 1..64, do: assert({:ok, %{status: :queued}} = Orchestration.steer(request, "Input #{n}"))
    assert {:error, %{reason: :queue_full}} = Orchestration.steer(request, "Overflow")
    MockLLM.release(mock, :held)
    assert {:ok, "After inputs"} = Request.await(request)
    assert texts(server) == ["Report" | Enum.map(1..64, &"Input #{&1}")]
    assert_script_done(mock)
  end

  test "queue loss fails the request instead of treating the queue as empty", %{jido: jido} do
    {mock, context} = mock([%{reply: {:wait, :held, {:text, "Cannot finish"}}}])
    server = start(jido)
    {:ok, request} = API.ask(server, "Report", context: context)
    assert_receive {:input_queue, queue}, 2_000
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    GenServer.stop(queue)
    MockLLM.release(mock, :held)
    assert {:error, _} = Request.await(request)
    assert Server.agent(server).state.reply == ""
    assert_script_done(mock)
  end

  test "cancellation discards undrained input and stops its queue", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:wait, :held, {:text, "Cancelled"}}}, %{reply: {:text, "Next"}}])

    server = start(jido)
    {:ok, request} = API.ask(server, "Report", context: context)
    assert_receive {:input_queue, queue}, 2_000
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert {:ok, _} = Orchestration.steer(request, "Discard me")
    monitor = Process.monitor(queue)
    assert :ok = Orchestration.cancel(request)
    assert_receive {:DOWN, ^monitor, :process, ^queue, _}, 2_000
    assert texts(server) == ["Report"]
    {:ok, next} = API.ask(server, "Next", context: context)
    assert {:ok, "Next"} = Request.await(next)
    assert texts(server) == ["Report", "Next"]
    assert_script_done(mock)
  end

  @tag history_case: "HIST-21/limits"
  test "consumption after the last allowed answer does not bypass the model budget", %{jido: jido} do
    {mock, context} = mock([%{reply: {:wait, :held, {:text, "Last allowed answer"}}}])

    server =
      start(jido, %{
        controls: %{
          max_iterations: 1,
          max_model_calls: 1,
          input: [JidoAI.Examples.Steering.ObserveQueue],
          timeout: 10_000
        }
      })

    {:ok, request, events} = API.ask_stream(server, "Report", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    assert {:ok, _} = Orchestration.steer(request, "Consumed without a second call")
    MockLLM.release(mock, :held)
    assert {:error, _} = Request.await(request)
    events = Enum.to_list(events)
    assert Enum.count(events, &(&1.kind == :llm_started)) == 1
    assert Enum.any?(events, &(&1.kind == :input_injected))
    assert List.last(events).kind == :request_failed
    assert texts(server) == ["Report", "Consumed without a second call"]
    assert_script_done(mock)
  end

  test "a later request projects committed history with one system instruction", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:text, "First answer"}}, %{reply: {:text, "Second answer"}}])

    server = start(jido)
    {:ok, first} = API.ask(server, "First query", context: context)
    assert {:ok, "First answer"} = Request.await(first)
    {:ok, second} = API.ask(server, "Second query", context: context)
    assert {:ok, "Second answer"} = Request.await(second)
    [_, wire] = MockLLM.report(mock).requests

    assert Enum.map(wire.body["messages"], & &1["role"]) == [
             "system",
             "user",
             "assistant",
             "user"
           ]

    assert Enum.at(wire.body["messages"], 2)["content"] == "First answer"
    assert texts(server) == ["First query", "Second query"]
    assert_script_done(mock)
  end

  test "one-Turn history commits with the result and rolls back on rejection", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "One Turn"}}, %{reply: {:text, "Rejected"}}])
    changes = %{requests: %{mode: :turn}, controls: %{input: [], timeout: 10_000}}
    server = start(jido, changes)
    assert {:ok, agent} = ask(server, context)
    assert Enum.map(conversation(agent), & &1.role) == [:user, :assistant]
    assert agent.state.reply == "One Turn"

    denied =
      start(jido, %{
        changes
        | controls: %{output: [JidoAI.Examples.AIRuntime.Reject], timeout: 10_000}
      })

    before = Server.snapshot(denied)
    assert {:error, _} = ask(denied, context)
    assert Server.snapshot(denied) == before
    assert_script_done(mock)
  end

  @tag history_case: "HIST-21/control-timeout"
  test "a control timeout does not prove that input was rejected", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:wait, :held, {:text, "First"}}}, %{reply: {:text, "After timeout"}}])

    server = start(jido)
    {:ok, request} = API.ask(server, "Report", context: context)
    assert_receive {:input_queue, queue}, 2_000
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    JidoAI.Examples.ToolEvents.attach_action(Jido.AI.Orchestration.ControlAction)
    :sys.suspend(queue)

    result =
      try do
        Orchestration.steer(request, "Delayed input", timeout: 1_000)
      after
        :sys.resume(queue)
      end

    assert {:error, _} = result
    assert_receive {:example_action_started, "ai_session_control"}, 2_000
    # The caller timed out, but the admitted control Turn still runs. Wait for
    # its queue write before allowing the model to finish and seal the queue.
    assert pending_before?(queue, System.monotonic_time(:millisecond) + 2_000)
    MockLLM.release(mock, :held)
    assert {:ok, "After timeout"} = Request.await(request)
    assert texts(server) == ["Report", "Delayed input"]
    assert_script_done(mock)
  end

  test "steering stays closed during structured output repair", %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:object, %{answer: ""}}},
        %{reply: {:wait, :repair, {:object, %{answer: "Repaired"}}}}
      ])

    {_, options} = Enum.find(Agent.definition().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))

    profile =
      options[:profiles].assistant
      |> Map.from_struct()
      |> Map.merge(%{
        tools: [],
        result: %{
          schema: Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)}),
          into: :reply,
          max_repairs: 1
        }
      })

    base = %{
      name: "repair_steering",
      schema:
        Zoi.object(%{
          reply: Zoi.map() |> Zoi.default(%{}),
          messages: Jido.AI.Thread.Projection.schema()
        }),
      routes: [{"ai.ask", Jido.AI.Authoring.ai(:assistant)}]
    }

    {:ok, definition} = Jido.AI.Authoring.lower(base, [profile])
    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    {:ok, request} = API.ask(server, "Report", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :repair, _}, 2_000
    assert {:error, %{reason: :closed}} = Orchestration.inject(request, "Too late for repair")
    MockLLM.release(mock, :repair)
    assert {:ok, %{answer: "Repaired"}} = Request.await(request)
    assert texts(server) == ["Report"]
    assert_script_done(mock)
  end

  defp pending_before?(queue, deadline) do
    cond do
      Jido.AI.PendingInputServer.has_pending?(queue) -> true
      System.monotonic_time(:millisecond) >= deadline -> false
      true -> pending_before?(queue, deadline)
    end
  end

  test "history fields and steering policy fail at the authoring boundary" do
    {_, options} = Enum.find(Agent.definition().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    profile = Map.from_struct(options[:profiles].assistant)
    base = %{name: "invalid_memory", schema: Agent.domain_schema(), routes: []}

    for field <- [:missing, :reply] do
      assert {:error, %{field: "memory.history"}} =
               Jido.AI.Authoring.lower(base, [%{profile | memory: %{history: field}}])
    end

    assert {:error, %{field: "requests"}} =
             Jido.AI.Profile.new(%{profile | requests: %{mode: :turn, steering: true}})
  end
end
