defmodule Jido.AI.Live.ReActStreamTimeoutLiveTest do
  @moduledoc """
  Live OpenAI acceptance checks for issue #381. A local relay holds real SSE bytes.

      JIDO_LIVE_MODEL=openai:gpt-4.1-mini \\
      mix test test/jido_ai/live/react_stream_timeout_live_test.exs --include live --include flaky --seed 0

  Requires OPENAI_API_KEY. Writes evidence to tmp/issue-381-live.jsonl.
  """
  use ExUnit.Case, async: false

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Reasoning.ReAct.{Config, Runner}
  alias Jido.AI.Request
  alias Jido.AI.TestSupport.LiveStreamRelay

  @moduletag :live
  @moduletag :flaky
  @moduletag timeout: 120_000
  @model System.get_env("JIDO_LIVE_MODEL", "openai:gpt-4.1-mini")
  @idle_ms System.get_env("JIDO_LIVE_IDLE_MS", "5000") |> String.to_integer()
  @report System.get_env("JIDO_LIVE_REPORT", "tmp/issue-381-live.jsonl")
  @prompt "Reply with exactly one lowercase word: pong"

  defmodule LiveAgent do
    use Jido.AI.Agent, name: "live_stream_timeout", model: :fast, tools: [], max_iterations: 1, max_tokens: 64
  end

  setup_all do
    assert String.starts_with?(@model, "openai:"), "This relay supports OpenAI models only"
    assert @idle_ms in 1_000..30_000, "Set JIDO_LIVE_IDLE_MS between 1000 and 30000"
    assert System.get_env("OPENAI_API_KEY") not in [nil, ""], "Set OPENAI_API_KEY before the live run"
    File.mkdir_p!(Path.dirname(@report))
    File.write!(@report, "")
    aliases = Application.get_env(:jido_ai, :model_aliases, %{})
    Application.put_env(:jido_ai, :model_aliases, Map.put(aliases, :fast, @model))
    on_exit(fn -> Application.put_env(:jido_ai, :model_aliases, aliases) end)
    :ok
  end

  setup do
    if is_nil(Process.whereis(Jido)), do: start_supervised!({Jido, name: Jido})
    :ok
  end

  test "live baseline succeeds" do
    {relay, config} = provider(:pass)
    events = Runner.stream(@prompt, config) |> Enum.to_list()
    assert [%{kind: :request_completed, data: %{result: answer}}] = terminal(events)
    assert is_binary(answer) and String.trim(answer) != ""
    assert_receive {:relay_closed, _, stats}, 5_000
    assert_provider(stats)
    assert stats.text_frames > 0
    report(:baseline, events, stats, %{relay_alive: Process.alive?(relay), native_timeout_ms: 60_000})
  end

  for mode <- [:before_response, :mid_stream] do
    @tag live_case: "runner_#{mode}"
    test "standalone #{mode} timeout closes a live stream" do
      {_relay, config} = provider(unquote(mode))
      tasks = start_supervised!(Task.Supervisor)
      task = Task.async(fn -> Runner.stream(@prompt, config, task_supervisor: tasks) |> Enum.to_list() end)
      {connection, held} = await_gate(unquote(mode))
      monitor = Process.monitor(connection)
      events = Task.await(task, @idle_ms + 5_000)
      assert_timeout(events)
      stats = assert_closed(connection, monitor)
      assert Task.Supervisor.children(tasks) == []
      report("runner_#{unquote(mode)}", events, stats, %{held: held, coordinator_stopped: true})
    end

    @tag live_case: "agent_#{mode}"
    test "delegated #{mode} timeout fails the parent and permits live reuse" do
      {_relay, config} = provider(unquote(mode))
      parent = start_supervised!({Jido.AgentServer, agent: LiveAgent})
      opts = request_options(config, @idle_ms)
      {:ok, %{request: handle, events: stream}} = LiveAgent.ask_stream(parent, @prompt, opts)
      {connection, held} = await_gate(unquote(mode))
      monitor = Process.monitor(connection)
      events = Enum.to_list(stream)
      assert_timeout(events)
      assert {:error, {:failed, :error, :stream_timeout}} = LiveAgent.await(handle, timeout: 2_000)
      stats = assert_closed(connection, monitor)
      {:ok, server} = Jido.AgentServer.state(parent)
      state = StratState.get(server.agent)
      assert state.status == :error
      assert state.active_request_id == nil
      assert state.react_worker_status == :ready
      assert Request.get_request(server.agent, handle.id).status == :failed
      assert Request.stream_sink(server.agent, handle.id) == nil
      worker = state.react_worker_pid
      assert_worker_idle(worker)
      send(connection, :release)

      {:ok, %{request: next, events: next_stream}} =
        LiveAgent.ask_stream(parent, @prompt, request_options(config, 60_000))

      next_events = Enum.to_list(next_stream)
      assert [%{kind: :request_completed}] = terminal(next_events)
      assert {:ok, answer} = LiveAgent.await(next, timeout: 2_000)
      assert is_binary(answer) and String.trim(answer) != ""
      {:ok, server} = Jido.AgentServer.state(parent)
      assert StratState.get(server.agent).react_worker_pid == worker
      assert Request.get_request(server.agent, handle.id).status == :failed
      id = handle.id
      refute_receive {:jido_ai_request_event, %{request_id: ^id}}, 100
      assert_receive {:relay_closed, _, reuse_stats}, 5_000
      assert_provider(reuse_stats)

      report("agent_#{unquote(mode)}", events, stats, %{
        held: held,
        parent_failed: true,
        worker_idle: true,
        same_worker_reused: true,
        reuse: event_summary(next_events),
        reuse_upstream: reuse_stats
      })
    end
  end

  test "explicit cancellation of a held live stream remains cancellation" do
    {_relay, config} = provider(:mid_stream)
    task = Task.async(fn -> Runner.stream(@prompt, config) |> Enum.to_list() end)
    {connection, _held} = await_gate(:mid_stream)
    monitor = Process.monitor(connection)
    send(task.pid, {:react_stream_cancel, :user_cancelled})
    events = Task.await(task, 5_000)
    assert [%{kind: :request_cancelled, data: %{reason: :user_cancelled}}] = terminal(events)
    stats = assert_closed(connection, monitor)
    report(:explicit_cancel, events, stats)
  end

  test "consumer halt closes a live stream without a timeout failure" do
    {_relay, config} = provider(:mid_stream)
    tasks = start_supervised!(Task.Supervisor)
    owner = self()

    task =
      Task.async(fn ->
        Runner.stream(@prompt, config, task_supervisor: tasks)
        |> Stream.take_while(fn
          %{kind: :llm_delta} ->
            send(owner, :consumer_ready)

            receive do
              :halt -> false
            end

          _ ->
            true
        end)
        |> Enum.to_list()
      end)

    {connection, _held} = await_gate(:mid_stream)
    assert_receive :consumer_ready, 5_000
    monitor = Process.monitor(connection)
    send(task.pid, :halt)
    events = Task.await(task, 5_000)
    assert terminal(events) == []
    stats = assert_closed(connection, monitor)
    assert Task.Supervisor.children(tasks) == []
    report(:consumer_halt, events, stats)
  end

  defp provider(mode) do
    relay = start_supervised!({LiveStreamRelay, owner: self(), modes: [mode]})

    config =
      Config.new(%{
        model: @model,
        tools: [],
        max_iterations: 1,
        stream_timeout_ms: 60_000,
        llm_opts: [
          api_key: "local-relay-only",
          base_url: LiveStreamRelay.url(relay),
          max_tokens: 64,
          max_retries: 0,
          receive_timeout: 60_000,
          req_http_options: [retry: false, receive_timeout: 60_000]
        ]
      })

    idle = if mode == :pass, do: 60_000, else: @idle_ms
    {relay, %{config | stream_timeout_ms: idle}}
  end

  defp request_options(config, idle) do
    [llm_opts: config.llm.llm_opts, stream_timeout_ms: idle, stream_event_timeout_ms: 65_000]
  end

  defp await_gate(mode) do
    receive do
      {:relay_held, connection, stats} ->
        assert_provider(stats)
        assert stats.held_bytes > 0
        assert stats.text_frames == if(mode == :mid_stream, do: 1, else: 0)
        {connection, stats}

      {:relay_rejected, _, status} ->
        flunk("The live provider rejected the request: HTTP #{status}")

      {:relay_error, _, error} ->
        flunk("The live provider connection failed: #{error}")
    after
      @idle_ms + 5_000 ->
        flunk("No real response reached the relay gate. Increase JIDO_LIVE_IDLE_MS and repeat this case.")
    end
  end

  defp assert_timeout(events) do
    assert [
             %{
               kind: :request_failed,
               data: %{error: :stream_timeout, error_type: :stream_timeout, timeout_ms: @idle_ms}
             } = failed
           ] = terminal(events)

    assert List.last(events) == failed
    assert Enum.all?(events, &(&1.request_id == failed.request_id and &1.run_id == failed.run_id))
    seqs = Enum.map(events, & &1.seq)
    assert seqs == Enum.sort(Enum.uniq(seqs))
    assert failed.llm_call_id == Enum.find(events, &(&1.kind == :llm_started)).llm_call_id
    assert failed.at_ms - Enum.at(events, -2).at_ms >= @idle_ms - 100
  end

  defp assert_provider(stats) do
    assert stats.upstream_status == 200
    assert is_binary(stats.upstream_request_id) and stats.upstream_request_id != ""
    assert stats.received_bytes > 0
  end

  defp assert_closed(connection, monitor) do
    assert_receive {:relay_closed, ^connection, %{reason: :client_closed, upstream_cancel_requested: true} = stats},
                   2_000

    assert_receive {:DOWN, ^monitor, :process, ^connection, :normal}, 2_000
    stats
  end

  defp assert_worker_idle(worker, attempts \\ 100)
  defp assert_worker_idle(_, 0), do: flunk("The worker did not become idle after timeout")

  defp assert_worker_idle(worker, attempts) do
    {:ok, server} = Jido.AgentServer.state(worker)
    state = StratState.get(server.agent)

    if state.status == :idle and state.runtime_task == nil and state.active_request_id == nil do
      :ok
    else
      Process.sleep(10)
      assert_worker_idle(worker, attempts - 1)
    end
  end

  defp terminal(events), do: Enum.filter(events, &Request.Stream.terminal_kind?(&1.kind))

  defp event_summary(events) do
    Enum.map(events, &Map.take(&1, [:kind, :seq, :at_ms, :request_id, :run_id, :llm_call_id]))
  end

  defp report(scenario, events, stats, extra \\ %{}) do
    result =
      Map.merge(
        %{
          scenario: scenario,
          passed: true,
          model: @model,
          native_timeout_ms: @idle_ms,
          events: event_summary(events),
          relay: stats
        },
        extra
      )

    line = Jason.encode!(result) <> "\n"
    File.write!(@report, line, [:append])
    IO.write(line)
  end
end
