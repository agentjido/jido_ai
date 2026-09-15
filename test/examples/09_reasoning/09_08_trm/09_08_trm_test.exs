defmodule JidoAI.Examples.TRMTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Authoring, Request, Orchestration}
  alias Jido.AI.Reasoning.TRM.{Machine, Reasoning, Supervision}
  alias JidoAI.Examples.TRM

  defp start(jido, changes \\ %{}) do
    assert {:ok, definition} = TRM.definition(changes)
    start_agent(jido, Jido.Agent.instantiate!(definition))
  end

  defp request(server, context, query \\ "Explain the answer"),
    do:
      Request.create_and_send(server, query,
        signal_type: "ai.trm.query",
        source: "/examples/trm",
        context: context,
        stream_to: self()
      )

  defp record(server, handle), do: Server.agent(server).state.requests[handle.id]
  defp machine(server, handle), do: record(server, handle).meta.reasoning.trm

  defp events(handle),
    do: handle |> Request.Stream.events(stream_event_timeout_ms: 1_000) |> Enum.to_list()

  test "one review cycle returns the latest improvement and keeps the scored answer", %{
    jido: jido
  } do
    {mock, context} = mock(TRM.script())
    server = start(jido)
    assert {:ok, handle} = request(server, context)
    assert {:ok, "Unreviewed improvement"} = Request.await(handle)
    state = machine(server, handle)
    assert state.status == :completed and state.termination_reason == :act_threshold
    assert state.best_score == 0.95 and state.best_answer == "First answer"
    assert state.current_answer == "Unreviewed improvement"
    assert state.answer_history == ["Unreviewed improvement"]
    assert state.supervision_step == 1 and state.act_triggered
    assert state.latent_state.step_count == 1 and length(state.latent_state.reasoning_trace) == 3
    assert state.usage.total_tokens == 45
    assert record(server, handle).meta.usage.total_tokens == 45
    assert record(server, handle).meta.model_calls == 3
    assert record(server, handle).method == :trm
    assert Server.agent(server).state.reply == "Unreviewed improvement"
    [reason, review, improve] = MockLLM.report(mock).requests
    assert reason.body["max_tokens"] == 1024 and reason.body["temperature"] == 0.2
    assert hd(reason.body["messages"])["content"] == Reasoning.default_reasoning_system_prompt()

    assert hd(review.body["messages"])["content"] ==
             Supervision.default_supervision_system_prompt()

    assert List.last(review.body["messages"])["content"] =~ "First answer"

    assert hd(improve.body["messages"])["content"] ==
             Supervision.default_improvement_system_prompt()

    assert List.last(improve.body["messages"])["content"] =~ "Missing detail"
    assert List.last(improve.body["messages"])["content"] =~ "Add detail"
    assert_script_done(mock)
  end

  test "a later review scores the prior improvement and preserves feedback and bounded trace", %{
    jido: jido
  } do
    script =
      TRM.cycle("Initial answer", 0.2, "Improved once") ++
        TRM.cycle("Second analysis", 0.4, "Improved twice") ++
        TRM.cycle("Third analysis", 0.6, "Best reviewed answer") ++
        TRM.cycle("Fourth analysis", 0.8, "Unreviewed final answer")

    {mock, context} = mock(script)
    server = start(jido, TRM.options(%{max_supervision_steps: 4, act_threshold: 1.0}))
    assert {:ok, handle} = request(server, context)
    assert {:ok, "Unreviewed final answer"} = Request.await(handle)
    state = machine(server, handle)
    assert state.termination_reason == :max_steps and state.supervision_step == 4
    refute state.act_triggered
    assert state.best_score == 0.8 and length(state.answer_history) == 4
    assert length(state.latent_state.reasoning_trace) == 10
    assert state.usage.total_tokens == 180
    wires = MockLLM.report(mock).requests
    assert List.last(Enum.at(wires, 3).body["messages"])["content"] =~ "Improved once"
    next_review = List.last(Enum.at(wires, 4).body["messages"])["content"]
    assert next_review =~ "Previous Feedback" and next_review =~ "0.2"
    assert next_review =~ "Improved once"
    refute next_review =~ "Second analysis"
    assert_script_done(mock)
  end

  test "convergence returns the latest improvement and retains the higher scored answer", %{
    jido: jido
  } do
    script =
      TRM.cycle("Best", 0.7, "Lower") ++
        TRM.cycle("Analyze lower", 0.69, "Last") ++
        TRM.cycle("Analyze last", 0.69, "Unreviewed")

    {mock, context} = mock(script)
    server = start(jido)
    assert {:ok, handle} = request(server, context)
    assert {:ok, "Unreviewed"} = Request.await(handle)
    state = machine(server, handle)
    assert state.termination_reason == :convergence_detected and state.act_triggered
    assert state.supervision_step == 3 and state.best_score == 0.7
    assert state.best_answer == "Best" and state.current_answer == "Unreviewed"
    assert state.act_state.history == [0.7, 0.69, 0.69]
    assert state.usage.total_tokens == 135
    assert_script_done(mock)
  end

  test "the step limit takes precedence over an ACT threshold reached in the same cycle", %{
    jido: jido
  } do
    {mock, context} = mock(TRM.script())
    server = start(jido, TRM.options(%{max_supervision_steps: 1}))
    assert {:ok, handle} = request(server, context)
    assert {:ok, "Unreviewed improvement"} = Request.await(handle)
    assert machine(server, handle).termination_reason == :max_steps
    refute machine(server, handle).act_triggered
    assert_script_done(mock)
  end

  test "zero review scores retain the legacy fallback to the current answer", %{jido: jido} do
    {mock, context} = mock(TRM.cycle("Zero scored", 0.0, "Current fallback"))
    server = start(jido, TRM.options(%{max_supervision_steps: 1}))
    assert {:ok, handle} = request(server, context)
    assert {:ok, "Current fallback"} = Request.await(handle)
    assert machine(server, handle).best_answer == nil
    assert machine(server, handle).best_score == 0.0
    assert_script_done(mock)
  end

  for {phase, completed} <- [reasoning: 0, supervision: 1, improvement: 2] do
    test "#{phase} failure keeps the raw cause and usage and permits a later request", %{
      jido: jido
    } do
      {mock, context} =
        mock(
          Enum.take(TRM.script(), unquote(completed)) ++
            [%{reply: {:stream, [], "length"}}] ++ TRM.script()
        )

      server = start(jido)
      assert {:ok, handle} = request(server, context)
      assert {:error, {:failed, {:incomplete_response, :length}, result}} = Request.await(handle)
      assert result.diagnostics.cause == {:incomplete_response, :length}
      assert result.diagnostics.phase == unquote(phase)
      assert result.trm.status == :error and result.trm.termination_reason == :error
      assert result.usage.total_tokens == (unquote(completed) + 1) * 15
      assert result.trm.usage == result.usage
      assert String.starts_with?(result.result, "Error: ")
      assert Server.agent(server).state.reply == nil
      assert List.last(events(handle)).kind == :request_failed
      assert {:ok, next} = request(server, context)
      assert {:ok, "Unreviewed improvement"} = Request.await(next)
      assert_script_done(mock)
    end
  end

  test "the common model budget stops before improvement without committing the scored answer", %{
    jido: jido
  } do
    {mock, context} = mock(Enum.take(TRM.script(), 2))
    server = start(jido, %{controls: %{TRM.source().controls | max_model_calls: 2}})
    assert {:ok, handle} = request(server, context)
    assert {:error, {:failed, reason, result}} = Request.await(handle)
    assert inspect(reason) =~ "limit"
    assert result.trm.best_answer == "First answer" and result.usage.total_tokens == 30
    assert result.diagnostics.phase == :improvement
    assert Server.agent(server).state.reply == nil
    assert_script_done(mock)
  end

  test "output control receives the selected answer and can stop the domain commit", %{jido: jido} do
    {mock, context} = mock(TRM.script())
    server = start(jido)
    assert {:ok, handle} = request(server, Map.put(context, :reject, :unapproved))
    assert {:error, {:failed, :unapproved, result}} = Request.await(handle)
    assert result.trm.best_answer == "First answer" and result.usage.total_tokens == 45
    assert Server.agent(server).state.reply == nil
    assert_script_done(mock)
  end

  test "five review cycles fit explicit common budgets and return the fifth improvement", %{
    jido: jido
  } do
    script =
      Enum.flat_map(Enum.with_index([0.1, 0.3, 0.5, 0.7, 0.8], 1), fn {score, step} ->
        TRM.cycle("Analysis #{step}", score, "Improvement #{step}")
      end)

    {mock, context} = mock(script)
    server = start(jido)
    assert {:ok, handle} = request(server, context)
    assert {:ok, "Improvement 5"} = Request.await(handle)
    assert machine(server, handle).supervision_step == 5
    assert machine(server, handle).termination_reason == :max_steps
    assert record(server, handle).meta.model_calls == 15
    assert record(server, handle).meta.usage.total_tokens == 225
    assert length(MockLLM.report(mock).requests) == 15
    assert_script_done(mock)
  end

  test "near maximum quality keeps the existing ACT stop below an explicit threshold of one", %{
    jido: jido
  } do
    {mock, context} = mock(TRM.cycle("High quality", 0.99, "Unreviewed"))
    server = start(jido, TRM.options(%{act_threshold: 1.0}))
    assert {:ok, handle} = request(server, context)
    assert {:ok, "Unreviewed"} = Request.await(handle)
    assert machine(server, handle).termination_reason == :act_threshold
    assert machine(server, handle).act_triggered
    assert machine(server, handle).best_score < machine(server, handle).act_threshold
    assert_script_done(mock)
  end

  test "non-streaming calls retain phase instructions and explicit generation options", %{
    jido: jido
  } do
    {mock, context} = mock(TRM.script())

    server =
      start(jido, %{
        instructions: "Use the supplied facts",
        requests: %{mode: :session, streaming: false},
        models: %{
          answer: %{model: MockLLM.model(), generation: [temperature: 0.4, max_tokens: 75]}
        }
      })

    assert {:ok, handle} = request(server, context)
    assert {:ok, "Unreviewed improvement"} = Request.await(handle)

    systems = [
      Reasoning.default_reasoning_system_prompt(),
      Supervision.default_supervision_system_prompt(),
      Supervision.default_improvement_system_prompt()
    ]

    for {wire, system} <- Enum.zip(MockLLM.report(mock).requests, systems) do
      refute wire.body["stream"]
      assert wire.body["temperature"] == 0.4 and wire.body["max_tokens"] == 75
      assert hd(wire.body["messages"])["content"] == "Use the supplied facts\n\n" <> system
      refute Map.has_key?(wire.body, "response_format")
    end

    assert_script_done(mock)
  end

  test "invalid method options typed results tools steering and rich queries fail before model work",
       %{jido: jido} do
    {mock, context} = mock([])

    for value <- [
          %{max_supervision_steps: 0},
          %{max_supervision_steps: 1.5},
          %{act_threshold: -0.1},
          %{act_threshold: 1.1},
          %{act_threshold: "0.9"},
          %{unknown: 1}
        ] do
      assert {:error, _} = TRM.definition(TRM.options(value))
    end

    for change <- [
          %{tools: [%{name: "work", target: JidoAI.Examples.ToT.Work}]},
          %{requests: %{mode: :session, steering: true}},
          %{result: %{schema: Zoi.string(), into: :reply}}
        ] do
      assert {:error, _} = TRM.definition(change)
    end

    server = start(jido)
    assert {:ok, handle} = request(server, context, [ReqLLM.Message.ContentPart.text("Rich")])
    assert {:error, _} = Request.await(handle)
    assert Server.agent(server).state.reply == nil
    assert_script_done(mock)
  end

  test "a request transformer cannot enable TRM tools and unsolicited tool work fails", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        hd(TRM.script()),
        %{reply: {:tools, [%{id: "unexpected", name: "tree_work", arguments: %{n: 1}}]}}
      ])

    server =
      start(jido, %{
        reasoning: Map.put(TRM.source().reasoning, :request_transformer, JidoAI.Examples.ToT.Transform)
      })

    assert {:ok, handle} = request(server, context)
    assert {:error, {:failed, {:unexpected_tool_calls, :trm}, result}} = Request.await(handle)
    assert result.trm.current_answer == "First answer" and result.usage.total_tokens == 30
    refute Enum.any?(events(handle), &(&1.kind == :tool_started))

    for wire <- MockLLM.report(mock).requests do
      refute Map.has_key?(wire.body, "tools")
      refute Map.has_key?(wire.body, "tool_choice")
    end

    assert_script_done(mock)
  end

  for {phase, completed} <- [supervision: 1, improvement: 2] do
    test "cancellation in #{phase} keeps the request pending until cancellation and permits new work",
         %{jido: jido} do
      {mock, context} =
        mock(
          Enum.take(TRM.script(), unquote(completed)) ++
            [%{reply: {:stream, [{:wait, :held_trm}], "stop"}}] ++ TRM.script()
        )

      server = start(jido)
      assert {:ok, handle} = request(server, context)
      assert_receive {:mock_llm_waiting, ^mock, :held_trm, provider}, 2_000
      monitor = Process.monitor(provider)
      assert record(server, handle).status == :pending
      assert Server.agent(server).state.reply == nil
      assert {:error, :busy} = request(server, context)
      assert :ok = Orchestration.cancel(handle, reason: :changed_task)
      assert {:error, {:cancelled, :changed_task}} = Request.await(handle)
      assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
      assert record(server, handle).meta.usage.total_tokens == unquote(completed) * 15
      assert {:ok, next} = request(server, context)
      assert {:ok, "Unreviewed improvement"} = Request.await(next)
      assert_script_done(mock)
    end
  end

  test "the total deadline closes supervision transport and preserves prior usage", %{jido: jido} do
    {mock, context} =
      mock([hd(TRM.script()), %{reply: {:stream, [{:wait, :trm_deadline}], "stop"}}])

    server = start(jido, %{controls: %{TRM.source().controls | timeout: 400}})
    assert {:ok, handle} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :trm_deadline, provider}, 2_000
    monitor = Process.monitor(provider)
    assert {:error, _} = Request.await(handle, timeout: 3_000)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert record(server, handle).status == :failed and Server.agent(server).state.reply == nil
    assert record(server, handle).meta.usage.total_tokens == 15
    assert_script_done(mock)
  end

  test "owner loss closes improvement transport and permits a new request", %{jido: jido} do
    {mock, context} =
      mock(
        Enum.take(TRM.script(), 2) ++
          [%{reply: {:stream, [{:wait, :lost_trm}], "stop"}}] ++ TRM.script()
      )

    server = start(jido)
    assert {:ok, handle} = request(server, context)
    assert_receive {:mock_llm_waiting, ^mock, :lost_trm, provider}, 2_000
    monitor = Process.monitor(provider)
    Process.exit(Server.children(server)[{:plugin, Orchestration.Plugin}].pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert {:error, :stream_interrupted} = Request.await(handle)
    assert Server.agent(server).state.reply == nil
    assert {:ok, next} = request(server, context)
    assert {:ok, "Unreviewed improvement"} = Request.await(next)
    assert_script_done(mock)
  end

  test "retained Machine rejects stale and repeated phase results and keeps nested usage and legacy errors" do
    {reasoning, _} =
      Machine.update(Machine.new(max_supervision_steps: 1), {:start, "Question", "first"})

    value = %{
      text: "First answer",
      usage: %{input_tokens: 2, output_tokens: 1, input_tokens_details: %{cached_tokens: 1}}
    }

    assert {^reasoning, []} =
             Machine.update(reasoning, {:reasoning_result, "stale", {:ok, value}})

    {supervision, _} = Machine.update(reasoning, {:reasoning_result, "first", {:ok, value, []}})

    assert {^supervision, []} =
             Machine.update(supervision, {:reasoning_result, "first", {:ok, value}})

    {improvement, _} =
      Machine.update(
        supervision,
        {:supervision_result, supervision.current_call_id, {:ok, %{value | text: "SCORE: 0.9"}}}
      )

    {completed, []} =
      Machine.update(
        improvement,
        {:improvement_result, improvement.current_call_id, {:ok, %{value | text: "Improved"}}}
      )

    assert completed.result == "Improved"

    assert completed.usage == %{
             input_tokens: 6,
             output_tokens: 3,
             total_tokens: 9,
             input_tokens_details: %{cached_tokens: 3}
           }

    assert {^completed, []} =
             Machine.update(
               completed,
               {:improvement_result, improvement.current_call_id, {:ok, value}}
             )

    assert Machine.from_map(Machine.to_map(completed)) == completed

    {failed, []} =
      Machine.update(
        supervision,
        {:supervision_result, supervision.current_call_id, {:error, :provider_down, []}}
      )

    assert failed.result == "Error: provider_down"
    assert failed.usage.total_tokens == 3 and failed.status == "error"
    refute Machine.from_map(Machine.to_map(%{failed | emit_telemetry?: false})).emit_telemetry?
  end

  test "phase events retain one request identity and project Signals and actual telemetry", %{
    jido: jido
  } do
    id = "trm_#{System.unique_integer([:positive])}"

    names = [
      [:jido, :ai, :llm, :complete],
      [:jido, :ai, :trm, :start],
      [:jido, :ai, :trm, :step],
      [:jido, :ai, :trm, :complete]
    ]

    :ok = :telemetry.attach_many(id, names, &JidoAI.Examples.Telemetry.handle/4, self())
    on_exit(fn -> :telemetry.detach(id) end)
    {mock, context} = mock(TRM.script())
    server = start(jido)
    assert {:ok, handle} = request(server, context)
    assert {:ok, _} = Request.await(handle)
    events = events(handle)
    completed = Enum.filter(events, &(&1.kind == :llm_completed))

    assert Enum.map(completed, & &1.data.reasoning_phase) == [
             :reasoning,
             :supervision,
             :improvement
           ]

    assert length(Enum.uniq_by(completed, & &1.llm_call_id)) == 3
    assert length(Enum.uniq_by(completed, & &1.data.phase_call_id)) == 3

    for event <- completed do
      assert event.request_id == handle.id and event.method == :trm
      assert event.data.supervision_step == 1
      assert {:ok, [signal, _]} = Jido.AI.Signal.from_event(event)
      assert signal.data.metadata.reasoning_phase == event.data.reasoning_phase
      call = event.llm_call_id

      assert_receive {:linear_telemetry, [:jido, :ai, :llm, :complete], _, %{llm_call_id: ^call, strategy: :trm}},
                     2_000
    end

    refute_receive {:linear_telemetry, [:jido, :ai, :trm, _], _, _}, 20
    assert length(Enum.filter(events, &(&1.kind == :request_started))) == 1
    assert length(Enum.filter(events, &(&1.kind == :request_completed))) == 1
    assert List.last(events).kind == :request_completed
    assert_script_done(mock)
  end

  test "a completed request keeps its review data when a later request starts fresh", %{
    jido: jido
  } do
    {mock, context} = mock(TRM.script() ++ TRM.cycle("Second answer", 0.97, "Second improvement"))
    server = start(jido)
    assert {:ok, first} = request(server, context, "First question")
    assert {:ok, "Unreviewed improvement"} = Request.await(first)
    old = record(server, first)
    assert {:ok, second} = request(server, context, "Second question")
    assert {:ok, "Second improvement"} = Request.await(second)
    assert record(server, first) == old
    assert machine(server, second).question == "Second question"
    assert machine(server, second).answer_history == ["Second improvement"]
    assert machine(server, second).usage.total_tokens == 45
    next_reason = List.last(Enum.at(MockLLM.report(mock).requests, 3).body["messages"])["content"]
    assert next_reason =~ "first reasoning step"
    refute next_reason =~ "First answer"
    assert_script_done(mock)
  end

  test "the retained Machine still emits legacy steps completion and errors" do
    id = "trm_legacy_#{System.unique_integer([:positive])}"
    names = for phase <- [:start, :step, :complete, :error], do: [:jido, :ai, :trm, phase]
    :ok = :telemetry.attach_many(id, names, &JidoAI.Examples.Telemetry.handle/4, self())
    on_exit(fn -> :telemetry.detach(id) end)

    {machine, _} =
      Machine.update(Machine.new(max_supervision_steps: 1), {:start, "Question", "legacy"})

    Enum.reduce(
      [
        {:reasoning_result, "Answer"},
        {:supervision_result, "SCORE: 0.9"},
        {:improvement_result, "Improved"}
      ],
      machine,
      fn {phase, text}, machine ->
        {next, _} =
          Machine.update(
            machine,
            {phase, machine.current_call_id, {:ok, %{text: text, usage: %{input_tokens: 2, output_tokens: 1}}}}
          )

        next
      end
    )

    assert_receive {:linear_telemetry, [:jido, :ai, :trm, :start], _, %{call_id: "legacy"}}

    for phase <- [:reasoning, :supervision, :improvement] do
      assert_receive {:linear_telemetry, [:jido, :ai, :trm, :step], _, %{phase: ^phase, step: 1}}
    end

    assert_receive {:linear_telemetry, [:jido, :ai, :trm, :complete], _,
                    %{usage: %{total_tokens: 9}, termination_reason: :max_steps}}

    {failed, []} =
      Machine.update(machine, {:reasoning_result, "legacy", {:error, :provider_down}})

    assert failed.result == "Error: provider_down"
    assert_receive {:linear_telemetry, [:jido, :ai, :trm, :error], _, %{error: :provider_down}}
  end

  test "DSL data Builder source JSON direct Flow and ordinary turns use the same recursive contract",
       %{jido: jido} do
    {mock, context} = mock(List.duplicate(TRM.script(), 6) |> List.flatten())
    source = TRM.source()
    assert {:ok, definition} = TRM.definition()
    assert definition == TRM.Agent.definition()
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
             Authoring.Codec.decode(TRM.base(), Jason.decode!(Jason.encode!(document)), registry)

    assert decoded == built and built == definition

    for value <- [TRM.Agent.definition(), definition, built, decoded] do
      server = start_agent(jido, Jido.Agent.instantiate!(value))
      assert {:ok, handle} = request(server, context)
      assert {:ok, "Unreviewed improvement"} = Request.await(handle)
      assert machine(server, handle).best_answer == "First answer"
    end

    assert {:ok, profile} = Jido.AI.Profile.new(source)
    assert {:ok, flow} = Authoring.reasoning_flow(profile)

    direct_context =
      Map.merge(context, %{agent_state: %{reply: nil}, jido_ai_profiles: %{assistant: profile}})

    assert {:ok, %{result: "Unreviewed improvement", meta: meta}} =
             Jido.Exec.run(flow, %{query: "Explain the answer"}, direct_context)

    assert meta.reasoning.trm.supervision_step == 1
    server = start(jido, %{requests: %{mode: :turn}})

    signal =
      Jido.Signal.new!("ai.trm.query", %{query: "Explain the answer"}, source: "/examples/trm")

    assert {:ok, agent} = Server.call(server, signal, context: context, timeout: 5_000)
    assert agent.state.reply == "Unreviewed improvement"
    assert_script_done(mock)
  end

  defp atoms(value) when is_atom(value), do: [value]
  defp atoms(value) when is_list(value), do: Enum.flat_map(value, &atoms/1)
  defp atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> atoms()
  defp atoms(%_{}), do: []

  defp atoms(value) when is_map(value),
    do: Enum.flat_map(value, fn {k, v} -> atoms(k) ++ atoms(v) end)

  defp atoms(_), do: []
end
