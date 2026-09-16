defmodule Jido.AI.Orchestration.ExecutionBridgeTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Orchestration.{ExecutionBinding, ExecutionBridge, Transcript}
  alias Jido.AI.Test.MockLLM

  defmodule Capture do
    @behaviour Jido.AI.Control
    def check(_, context) do
      send(context.observer, {:execution_context, context})
      :ok
    end
  end

  defmodule HistoryGate do
    use Jido.Plugin

    def prepare(command, opts) do
      if command.signal.type == Jido.AI.Orchestration.history_type() do
        send(opts[:observer], {:history_gate, self()})

        receive do
          :release -> {:ok, command}
          :reject -> {:error, :entry_denied}
        end
      else
        {:ok, command}
      end
    end
  end

  defmodule Assistant do
    use Jido.AI.Agent, name: "execution_bridge"

    agent do
      schema Zoi.object(%{
               answer: Zoi.string() |> Zoi.default(""),
               context: Jido.Session.schema() |> Zoi.default(Jido.Session.new())
             })

      ai :assistant do
        model MockLLM.model()

        controls do
          input Capture
          timeout 30_000
          steering true
        end

        memory do
          history(:context)
        end

        observability do
          store_content true
          stream_content true
          diagnostics_content true
          emit_signals false
        end

        result into: :answer
      end
    end

    routes do
      signal_source "/test/bridge"
      route "bridge.ask", ai: :assistant
    end
  end

  # Real core persistence: store the bytes, then lose the write reply.
  defmodule Store do
    use Elixir.Agent
    @behaviour Jido.Persistence.Adapter
    def start_link(_), do: Elixir.Agent.start_link(fn -> %{records: %{}, failure: nil, attempts: 0} end)
    def arm(store, failure), do: Elixir.Agent.update(store, &%{&1 | failure: failure})
    def attempts(store), do: Elixir.Agent.get(store, & &1.attempts)

    def get(key, opts) do
      Elixir.Agent.get(opts[:store], fn s ->
        case Map.fetch(s.records, key) do
          {:ok, bytes} -> {:ok, bytes}
          :error -> {:error, :not_found}
        end
      end)
    end

    def put(key, bytes, opts), do: Elixir.Agent.update(opts[:store], &put_in(&1.records[key], bytes))
    def delete(key, opts), do: Elixir.Agent.update(opts[:store], &%{&1 | records: Map.delete(&1.records, key)})

    def compare_and_swap(key, expected, bytes, opts) do
      result =
        Elixir.Agent.get_and_update(opts[:store], fn state ->
          cond do
            Map.get(state.records, key, :not_found) != expected ->
              {{:error, :conflict}, state}

            state.failure == nil ->
              {:ok, put_in(state.records[key], bytes)}

            true ->
              {state.failure, state |> put_in([:records, key], bytes) |> Map.update!(:attempts, &(&1 + 1))}
          end
        end)

      case result do
        :indeterminate -> {:error, :indeterminate}
        :raise -> raise "stored entry, lost reply"
        other -> other
      end
    end
  end

  setup do
    jido = :"bridge_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})
    {:ok, jido: jido}
  end

  defp start(jido, opts \\ []) do
    definition = Assistant.definition()

    definition =
      if opts[:gate],
        do: %{definition | plugins: definition.plugins ++ [{HistoryGate, observer: self()}]},
        else: definition

    instance = Jido.Agent.instantiate!(definition)
    {:ok, server} = Jido.start_agent(jido, instance, Keyword.take(opts, [:persistence, :restore]))
    mock = start_supervised!({MockLLM, observer: self(), script: [%{reply: {:wait, :held, {:text, "Done"}}}]})

    options =
      MockLLM.options(mock)
      |> Keyword.put(:receive_timeout, 20_000)
      |> Keyword.put(:req_http_options, retry: false, receive_timeout: 20_000)

    caller = %{observer: self(), ai: %{assistant: %{options: options}}, jido_ai_execution: :forged}
    {:ok, handle} = Assistant.ask(server, "Work", context: caller, stream_to: self(), stream: false)
    assert_receive {:execution_context, context}, 2_000
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000
    {server, handle, context, mock, instance}
  end

  defp entry, do: %{role: :assistant, content: "Committed marker"}
  defp history(server), do: Jido.AgentServer.agent(server).state.context

  def recovery_event(_, _, meta, {observer, id}) do
    if meta.request_id == id, do: send(observer, {:recovered_terminal, self()})
  end

  test "trusted admission replaces caller ownership and keeps live resources out of Agent state", %{jido: jido} do
    {server, handle, context, mock, _} = start(jido)
    assert {:ok, %ExecutionBinding{} = binding} = ExecutionBinding.fetch(context)
    assert binding.request_id == handle.id
    assert binding.agent_server == server
    assert binding.coordinator == Jido.AgentServer.children(server)[{:plugin, Jido.AI.Orchestration.Plugin}].pid
    assert is_pid(binding.input_queue)
    assert {:error, :invalid_execution_binding} = ExecutionBinding.fetch(put_in(context.jido_ai_execution.source, nil))
    assert {:error, _} = Jido.Action.validate_static_data(binding)
    assert :ok = Jido.Action.validate_static_data(Jido.AgentServer.agent(server).state)
    refute Map.has_key?(context, :jido_ai_checkpoint)
    assert :ok = MockLLM.release(mock, :held)
    assert {:ok, "Done"} = Assistant.await(handle)
    assert :ok = Jido.Action.validate_static_data(Jido.AgentServer.agent(server).state)
  end

  test "ownerless calls are explicit, while missing or malformed managed bindings fail" do
    assert {:ok, :unmanaged} = ExecutionBridge.report(%{}, {:activity, :progress})
    assert {:ok, :unmanaged} = ExecutionBridge.commit_entries(%{}, [entry()])
    assert {:ok, %{history_delta: [_]}} = Transcript.record(%{history_delta: []}, [entry()], %{})
    assert {:ok, []} = ExecutionBridge.input(%{}, :drain)
    assert :sealed = ExecutionBridge.input(%{}, :seal_if_empty)
    assert {:error, :checkpoint_owner_required} = ExecutionBridge.pause(%{}, :before_llm, %{})
    assert {:error, :invalid_execution_report} = ExecutionBridge.report(%{}, {:unexpected, :fact})
    assert {:error, :invalid_execution_binding} = ExecutionBinding.new(%{})

    for {context, reason} <- [
          {%{jido_ai_execution: nil}, :invalid_execution_binding},
          {%{jido_ai_execution: %{}}, :invalid_execution_binding},
          {%{jido_ai_admission_profile: :assistant}, :missing_execution_binding}
        ] do
      assert {:error, ^reason} = ExecutionBridge.report(context, {:activity, :progress})
      assert {:error, ^reason} = ExecutionBridge.commit_entries(context, [])
      assert {:error, ^reason} = ExecutionBridge.input(context, :seal)
      assert {:error, ^reason} = ExecutionBridge.checkpoint(context)
      assert {:error, ^reason} = ExecutionBridge.snapshot(context)
    end
  end

  for stream <- [false, true] do
    test "direct Model.Generate stays ownerless for stream #{stream}" do
      mock = start_supervised!({MockLLM, script: [%{reply: {:text, "Direct"}}]})

      params = %{
        model: MockLLM.model(),
        messages: ReqLLM.Context.new([ReqLLM.Context.user("Hi")]),
        schema: nil,
        options: MockLLM.options(mock),
        stream: unquote(stream)
      }

      assert {:error, %{details: %{jido_ai_cause: :invalid_execution_binding}}} =
               Jido.AI.Model.Generate.run(params, %{jido_ai_execution: :bad})

      assert %{requests: []} = MockLLM.report(mock)
      assert {:ok, %{response: response}} = Jido.AI.Model.Generate.run(params, %{})
      assert ReqLLM.Response.text(response) == "Direct"
      assert %{remaining: [], unexpected: []} = MockLLM.report(mock)
    end
  end

  test "progress is ordered observation, not an entry commit", %{jido: jido} do
    {server, handle, context, _, _} = start(jido)
    before = history(server)
    assert {:ok, %{seq: seq}} = ExecutionBridge.snapshot(context)
    assert {:ok, :observed} = ExecutionBridge.report(context, {:usage, nil})

    for text <- ["one", "two"] do
      assert {:ok, :observed} =
               ExecutionBridge.report(context, {:event, :llm_delta, %{delta: text, chunk_type: :content}})
    end

    assert {:ok, %{seq: next}} = ExecutionBridge.snapshot(context)
    assert next == seq + 2
    assert history(server) == before
    assert :ok = Jido.AI.Orchestration.cancel(handle)
    assert {:error, :cancelled} = Assistant.await(handle)
    events = Enum.to_list(Jido.AI.Request.Stream.events(handle))
    assert Enum.map(events, & &1.seq) == Enum.to_list(1..length(events))
    assert List.last(events).kind == :request_cancelled
    assert {:ok, :ignored} = ExecutionBridge.report(context, {:usage, %{total_tokens: 999}})
    assert {:error, :stale_execution} = ExecutionBridge.commit_entries(context, [entry()])
    assert {:error, :stale_execution} = ExecutionBridge.input(context, :drain)
    assert {:error, :stale_execution} = ExecutionBridge.pause(context, :before_llm, %{})
    assert {:error, :stale_checkpoint} = ExecutionBridge.acknowledge(server, handle.id, "old")
  end

  test "wrong runs cannot change progress, entries, or the queue", %{jido: jido} do
    {_, handle, context, _, _} = start(jido)
    stale = put_in(context.jido_ai_execution.run_id, "other")
    assert {:ok, :ignored} = ExecutionBridge.report(stale, {:failure_type, :forged})
    assert {:error, :stale_execution} = ExecutionBridge.commit_entries(stale, [entry()])

    assert {:error, :stale_execution} =
             ExecutionBridge.commit_entries(put_in(stale.jido_ai_execution.retain_history?, false), [entry()])

    assert {:error, :stale_execution} = ExecutionBridge.input(stale, :seal)
    assert {:error, :stale_execution} = ExecutionBridge.snapshot(stale)
    assert :ok = Jido.AI.Orchestration.cancel(handle)
  end

  test "queue drain and sealing use the same active owner", %{jido: jido} do
    {_, handle, context, _, _} = start(jido)
    assert {:ok, %{status: :queued}} = Jido.AI.Orchestration.steer(handle, "First")
    assert {:ok, %{status: :queued}} = Jido.AI.Orchestration.inject(handle, "Second")
    assert :pending = ExecutionBridge.input(context, :seal_if_empty)
    assert {:ok, [%{content: "First"}, %{content: "Second"}]} = ExecutionBridge.input(context, :drain)
    assert :sealed = ExecutionBridge.input(context, :seal_if_empty)
    assert {:error, %{reason: :closed}} = Jido.AI.Orchestration.steer(handle, "Late")
    assert :ok = Jido.AI.Orchestration.cancel(handle)
  end

  test "entry commit waits at core admission without blocking Coordinator progress", %{jido: jido} do
    {server, handle, context, _, _} = start(jido, gate: true)
    task = Task.async(fn -> Transcript.record(%{history_delta: []}, [entry()], context) end)
    assert_receive {:history_gate, gate}, 2_000
    assert Task.yield(task, 0) == nil
    assert {:ok, :observed} = ExecutionBridge.report(context, {:activity, :progress})
    send(gate, :release)
    assert {:ok, %{history_delta: [%{content: "Committed marker"}]}} = Task.await(task)
    assert {:ok, messages} = Jido.AI.Thread.Projection.evidence_messages(history(server))
    entries = Jido.AI.Model.Messages.entries(messages)
    assert Enum.count(entries, &match?([%{type: :text, text: "Committed marker"}], &1.content)) == 1
    assert :ok = Jido.AI.Orchestration.cancel(handle)
  end

  test "a rejected entry commit does not return a local history delta or retry", %{jido: jido} do
    {server, handle, context, _, _} = start(jido, gate: true)
    before = history(server)
    task = Task.async(fn -> Transcript.record(%{history_delta: []}, [entry()], context) end)
    assert_receive {:history_gate, gate}, 2_000
    send(gate, :reject)
    assert {:error, {:execution_commit_rejected, _}} = Task.await(task)
    assert history(server) == before
    refute_receive {:history_gate, _}, 30
    assert :ok = Jido.AI.Orchestration.cancel(handle)
  end

  test "owner loss is not an ownerless success", %{jido: jido} do
    {server, handle, context, _, _} = start(jido)

    assert {:ok, :observed} =
             ExecutionBridge.report(context, {:output, :output_started, %{status: :started}, %{schema_summary: %{}}})

    assert {:ok, :committed} = ExecutionBridge.commit_entries(context, [entry()])
    handler = {__MODULE__, make_ref()}
    :ok = :telemetry.attach(handler, [:jido, :ai, :request, :failed], &__MODULE__.recovery_event/4, {self(), handle.id})
    on_exit(fn -> :telemetry.detach(handler) end)
    owner = context.jido_ai_execution.coordinator
    monitor = Process.monitor(owner)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, _}, 2_000
    assert {:error, :execution_owner_unavailable} = ExecutionBridge.report(context, {:activity, :progress})
    assert {:error, :execution_owner_unavailable} = ExecutionBridge.commit_entries(context, [entry()])
    assert {:error, :execution_owner_unavailable} = ExecutionBridge.input(context, :drain)
    assert {:error, :stream_interrupted} = Assistant.await(handle)
    assert_receive {:recovered_terminal, replacement}, 2_000
    assert :ok = GenServer.call(replacement, :ready)
    assert Jido.AgentServer.children(server)[{:plugin, Jido.AI.Orchestration.Plugin}].pid == replacement
    assert Jido.AgentServer.agent(server).state.requests[handle.id].meta.output.status == :error
  end

  test "a core call timeout is unknown and does not replay the staged entries", %{jido: jido} do
    {server, handle, context, _, _} = start(jido, gate: true)
    task = Task.async(fn -> ExecutionBridge.commit_entries(context, [entry()]) end)
    assert_receive {:history_gate, gate}, 2_000
    assert {:error, {:execution_commit_unknown, _}} = Task.await(task, 6_000)
    # Core can still finish after the caller's deadline. No replay is allowed.
    send(gate, :release)
    refute_receive {:history_gate, _}, 30
    assert {:ok, :observed} = ExecutionBridge.report(context, {:activity, :progress})
    assert :ok = Jido.AI.Orchestration.cancel(handle)
    assert {:error, :cancelled} = Assistant.await(handle)
    assert :ok = Jido.Action.validate_static_data(Jido.AgentServer.agent(server).state)
  end

  for failure <- [:indeterminate, :raise] do
    test "a #{failure} entry commit reply is unknown and never retried", %{jido: jido} do
      store = start_supervised!(Store)
      adapter = {Store, store: store}
      {server, handle, context, _, instance} = start(jido, persistence: adapter, restore: false)
      monitor = Process.monitor(server)
      Store.arm(store, unquote(failure))
      assert {:error, {:execution_commit_unknown, _}} = ExecutionBridge.commit_entries(context, [entry()])
      assert_receive {:DOWN, ^monitor, :process, ^server, _}, 2_000
      assert Store.attempts(store) == 1

      assert {:ok, restored, _} =
               Jido.Persistence.load_agent_with_revision(adapter, Assistant, instance.id, instance: jido)

      assert restored.state.requests[handle.id].status == :pending
      assert {:ok, messages} = Jido.AI.Thread.Projection.evidence_messages(restored.state.context)
      entries = Jido.AI.Model.Messages.entries(messages)
      assert Enum.count(entries, &match?([%{type: :text, text: "Committed marker"}], &1.content)) == 1
    end
  end

  test "execution steps do not use the owner process protocol" do
    root = Path.expand("../../..", __DIR__)

    worker_paths =
      Path.wildcard(Path.join(root, "lib/jido_ai/execution/**/*.ex")) ++
        [Path.join(root, "lib/jido_ai/model/generate.ex")]

    paths = worker_paths ++ [Path.join(root, "lib/jido_ai/reasoning/react/runner.ex")]

    assert length(paths) > 20

    for path <- paths do
      source = File.read!(path)
      refute source =~ "GenServer.call", path
      # The standalone adapter seals its caller's queue even if admission fails.
      # This is resource cleanup, not an active Flow input operation.
      if path in worker_paths, do: refute(source =~ ~r/PendingInputServer\.(drain|seal|stop|enqueue)/, path)
      refute source =~ ~r/jido_ai_(events|request_record|input_queue|input_source|managed|server)\b/, path
    end
  end
end
