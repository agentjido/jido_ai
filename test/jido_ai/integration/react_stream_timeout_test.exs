defmodule Jido.AI.Integration.ReActStreamTimeoutTest do
  use ExUnit.Case, async: false

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Reasoning.ReAct.{Config, Runner, State}
  alias Jido.AI.Request
  alias Jido.AI.TestSupport.ReActTimeoutServer

  defmodule TimeoutAgent do
    use Jido.AI.Agent,
      name: "react_stream_timeout",
      model: %{provider: :openai, id: "gpt-4o-mini", extra: %{wire: %{protocol: "openai_chat"}}},
      tools: [],
      stream_timeout_ms: 500
  end

  defmodule ResponsesTimeoutAgent do
    use Jido.AI.Agent,
      name: "react_responses_stream_timeout",
      model: "openai:gpt-4.1-mini",
      tools: [],
      stream_timeout_ms: 500
  end

  setup do
    if is_nil(Process.whereis(Jido)), do: start_supervised!({Jido, name: Jido})
    :ok
  end

  for wire <- [:chat, :responses], mode <- [:before_response, :mid_stream] do
    test "Runner emits a terminal timeout failure for #{wire} #{mode}" do
      {config, _server} = provider([unquote(mode)], unquote(wire))
      tasks = start_supervised!(Task.Supervisor)
      owner = self()

      task =
        Task.async(fn ->
          events =
            Runner.stream("Work", config, request_id: "timeout", run_id: "timeout-run", task_supervisor: tasks)
            |> Enum.to_list()

          send(owner, {:remaining_messages, Process.info(self(), :messages)})
          events
        end)

      assert_receive {:provider_waiting, provider}, 2_000
      monitor = Process.monitor(provider)
      events = Task.await(task, 3_000)
      assert_timeout(events, "timeout", "timeout-run")
      assert_receive {:provider_closed, ^provider}, 2_000
      assert_receive {:DOWN, ^monitor, :process, ^provider, :normal}, 2_000
      assert Task.Supervisor.children(tasks) == []
      assert_receive {:remaining_messages, {:messages, messages}}
      refute Enum.any?(messages, &match?({:react_runner, _, _, _}, &1))
      refute Enum.any?(messages, &match?({:react_runner, _, _}, &1))
      if unquote(mode) == :mid_stream, do: assert(Enum.any?(events, &(&1.kind == :llm_delta)))
    end

    test "delegated Agent finalizes #{wire} #{mode} timeout and reuses its worker" do
      {config, _server} = provider([unquote(mode), :success], unquote(wire))
      agent = if unquote(wire) == :responses, do: ResponsesTimeoutAgent, else: TimeoutAgent
      parent = start_supervised!({Jido.AgentServer, agent: agent})
      opts = [llm_opts: config.llm.llm_opts, stream_event_timeout_ms: 3_000]
      assert {:ok, %{request: request, events: stream}} = agent.ask_stream(parent, "Work", opts)
      assert_receive {:provider_waiting, provider}, 2_000
      monitor = Process.monitor(provider)
      events = Enum.to_list(stream)
      assert_timeout(events, request.id, request.id)
      assert {:error, {:failed, :error, :stream_timeout}} = agent.await(request, timeout: 3_000)
      assert_receive {:provider_closed, ^provider}, 2_000
      assert_receive {:DOWN, ^monitor, :process, ^provider, :normal}, 2_000

      {:ok, server} = Jido.AgentServer.state(parent)
      state = StratState.get(server.agent)
      assert state.status == :error
      assert state.active_request_id == nil
      assert state.react_worker_status == :ready
      assert Request.get_request(server.agent, request.id).status == :failed
      assert Request.stream_sink(server.agent, request.id) == nil
      if unquote(mode) == :mid_stream, do: assert(Enum.any?(events, &(&1.kind == :llm_delta)))
      worker = state.react_worker_pid
      {:ok, worker_server} = Jido.AgentServer.state(worker)
      worker_state = StratState.get(worker_server.agent)
      assert worker_state.status == :idle
      assert worker_state.runtime_task == nil
      assert worker_state.active_request_id == nil

      # A released provider cannot send a late completion after transport cleanup.
      send(provider, :release)
      assert {:ok, %{request: next, events: next_stream}} = agent.ask_stream(parent, "Next", opts)
      next_events = Enum.to_list(next_stream)
      assert [%{kind: :request_completed}] = terminal_events(next_events)
      assert {:ok, "Done"} = agent.await(next, timeout: 3_000)
      {:ok, server} = Jido.AgentServer.state(parent)
      assert StratState.get(server.agent).react_worker_pid == worker
      assert Request.get_request(server.agent, request.id).status == :failed
      id = request.id
      refute_receive {:jido_ai_request_event, %{request_id: ^id}}, 100
    end
  end

  test "a promptly released HTTP provider completes normally" do
    {config, _server} = provider([:before_response])
    task = Task.async(fn -> Runner.stream("Work", config) |> Enum.to_list() end)
    assert_receive {:provider_waiting, provider}, 2_000
    send(provider, :release)
    events = Task.await(task, 3_000)
    assert [%{kind: :request_completed, data: %{result: "Done"}}] = terminal_events(events)
  end

  test "a continued run keeps its request identity and sequence on timeout" do
    {config, _server} = provider([:before_response])
    state = %{State.new("Work", nil, request_id: "continued", run_id: "continued-run") | seq: 40}
    task = Task.async(fn -> Runner.stream_from_state(state, config) |> Enum.to_list() end)
    assert_receive {:provider_waiting, provider}, 2_000
    events = Task.await(task, 3_000)
    assert_timeout(events, "continued", "continued-run")
    assert Enum.map(events, & &1.seq) == [41, 42]
    assert_receive {:provider_closed, ^provider}, 2_000
  end

  test "completion queued before coordinator exit remains the only terminal event" do
    {config, _server} = provider([:mid_stream])
    tasks = start_supervised!(Task.Supervisor)
    owner = self()

    task =
      Task.async(fn ->
        Runner.stream("Work", config, task_supervisor: tasks)
        |> Stream.each(fn
          %{kind: :llm_delta, data: %{delta: "Partial "}} ->
            send(owner, :consumer_paused)

            receive do
              :resume -> :ok
            end

          _ ->
            :ok
        end)
        |> Enum.to_list()
      end)

    assert_receive {:provider_waiting, provider}, 2_000
    assert_receive :consumer_paused, 2_000
    [coordinator] = Task.Supervisor.children(tasks)
    monitor = Process.monitor(coordinator)
    send(provider, :release)
    assert_receive {:DOWN, ^monitor, :process, ^coordinator, :normal}, 2_000
    send(task.pid, :resume)
    events = Task.await(task, 3_000)
    assert [%{kind: :request_completed, data: %{result: "Partial Done"}}] = terminal_events(events)
  end

  test "explicit cancellation remains cancellation during a held HTTP stream" do
    {config, _server} = provider([:mid_stream])
    task = Task.async(fn -> Runner.stream("Work", config) |> Enum.to_list() end)
    assert_receive {:provider_waiting, provider}, 2_000
    send(task.pid, {:react_stream_cancel, :user_cancelled})
    events = Task.await(task, 3_000)
    assert [%{kind: :request_cancelled, data: %{reason: :user_cancelled}}] = terminal_events(events)
    assert_receive {:provider_closed, ^provider}, 2_000
  end

  test "consumer halt closes HTTP without a timeout failure" do
    {config, _server} = provider([:mid_stream])
    task = Task.async(fn -> Runner.stream("Work", config) |> Enum.take(3) end)
    assert_receive {:provider_waiting, provider}, 2_000
    events = Task.await(task, 3_000)
    assert Enum.map(events, & &1.kind) == [:request_started, :llm_started, :llm_delta]
    assert terminal_events(events) == []
    assert_receive {:provider_closed, ^provider}, 2_000
  end

  defp provider(modes, wire \\ :chat) do
    server = start_supervised!({ReActTimeoutServer, owner: self(), modes: modes, wire: wire})

    model =
      case wire do
        :chat ->
          {:ok, model} = ReqLLM.model("openai:gpt-4o-mini")
          %{model | extra: Map.put(model.extra || %{}, :wire, %{protocol: "openai_chat"})}

        :responses ->
          "openai:gpt-4.1-mini"
      end

    config =
      Config.new(%{
        model: model,
        tools: [],
        stream_timeout_ms: 500,
        llm_opts: [
          api_key: "local-test",
          base_url: ReActTimeoutServer.url(server),
          receive_timeout: 5_000,
          req_http_options: [retry: false, receive_timeout: 5_000]
        ]
      })

    {config, server}
  end

  defp assert_timeout(events, request_id, run_id) do
    assert [
             %{
               kind: :request_failed,
               request_id: ^request_id,
               run_id: ^run_id,
               data: %{error: :stream_timeout, error_type: :stream_timeout}
             } = failed
           ] = terminal_events(events)

    assert List.last(events) == failed
    assert Enum.all?(events, &(&1.request_id == request_id and &1.run_id == run_id))
    seqs = Enum.map(events, & &1.seq)
    assert seqs == Enum.sort(Enum.uniq(seqs))
    assert failed.llm_call_id == Enum.find(events, &(&1.kind == :llm_started)).llm_call_id
  end

  defp terminal_events(events), do: Enum.filter(events, &Request.Stream.terminal_kind?(&1.kind))
end
