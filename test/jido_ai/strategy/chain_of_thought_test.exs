defmodule Jido.AI.Reasoning.ChainOfThought.StrategyTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive, as: AgentDirective
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Reasoning.ChainOfThought.Machine
  alias Jido.AI.Directive
  alias Jido.AI.Reasoning.ChainOfThought.Strategy, as: ChainOfThought

  defp create_agent(opts \\ []) do
    %Jido.Agent{
      id: "test-agent",
      name: "test",
      state: %{}
    }
    |> then(fn agent ->
      ctx = %{strategy_opts: opts}
      {agent, []} = ChainOfThought.init(agent, ctx)
      agent
    end)
  end

  defp instruction(action, params) do
    %Jido.Instruction{action: action, params: params}
  end

  defp worker_event(kind, request_id, seq, data) do
    %{
      id: "evt_#{seq}",
      seq: seq,
      at_ms: 1_700_000_000_000 + seq,
      run_id: request_id,
      request_id: request_id,
      iteration: 1,
      kind: kind,
      llm_call_id: "cot_call_#{request_id}",
      tool_call_id: nil,
      tool_name: nil,
      data: data
    }
  end

  describe "init/2" do
    test "initializes delegated CoT state" do
      agent = create_agent()
      state = StratState.get(agent, %{})

      assert state[:status] == :idle
      assert state[:steps] == []
      assert state[:config].runtime_adapter == true
      assert state[:cot_worker_status] == :missing
    end

    test "uses default model when not specified" do
      agent = create_agent()
      state = StratState.get(agent, %{})
      assert state[:config].model == "anthropic:claude-haiku-4-5"
    end

    test "resolves model aliases" do
      agent = create_agent(model: :fast)
      state = StratState.get(agent, %{})
      assert state[:config].model == Jido.AI.resolve_model(:fast)
    end

    test "uses default system prompt when not provided" do
      agent = create_agent()
      state = StratState.get(agent, %{})
      assert state[:config].system_prompt == Machine.default_system_prompt()
    end
  end

  describe "action_spec/1" do
    test "returns spec for start action" do
      spec = ChainOfThought.action_spec(ChainOfThought.start_action())
      assert spec.name == "cot.start"
      assert spec.doc =~ "delegated"
    end

    test "returns spec for legacy llm actions" do
      assert ChainOfThought.action_spec(ChainOfThought.llm_result_action()).name == "cot.llm_result"
      assert ChainOfThought.action_spec(ChainOfThought.llm_partial_action()).name == "cot.llm_partial"
    end
  end

  describe "signal_routes/1" do
    test "returns delegated worker routes" do
      routes = ChainOfThought.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["ai.cot.query"] == {:strategy_cmd, :cot_start}
      assert route_map["ai.cot.worker.event"] == {:strategy_cmd, :cot_worker_event}
      assert route_map["jido.agent.child.started"] == {:strategy_cmd, :cot_worker_child_started}
      assert route_map["jido.agent.child.exit"] == {:strategy_cmd, :cot_worker_child_exit}
      assert route_map["ai.request.started"] == Jido.Actions.Control.Noop
      assert route_map["ai.request.completed"] == Jido.Actions.Control.Noop
      assert route_map["ai.request.failed"] == Jido.Actions.Control.Noop
      assert route_map["ai.llm.response"] == Jido.Actions.Control.Noop
      assert route_map["ai.llm.delta"] == Jido.Actions.Control.Noop
    end
  end

  describe "cmd/3 delegated lifecycle" do
    test "start emits SpawnAgent directive when worker is missing" do
      agent = create_agent()
      start = instruction(ChainOfThought.start_action(), %{prompt: "What is 2+2?", request_id: "req_cot_1"})

      {agent, directives} = ChainOfThought.cmd(agent, [start], %{})

      assert [%AgentDirective.SpawnAgent{} = spawn] = directives
      assert spawn.tag == :cot_worker
      assert spawn.agent == Jido.AI.Reasoning.ChainOfThought.Worker.Agent

      state = StratState.get(agent, %{})
      assert state[:status] == :reasoning
      assert state[:active_request_id] == "req_cot_1"
      assert state[:pending_worker_start].prompt == "What is 2+2?"
    end

    test "child started flushes deferred start event to worker pid" do
      agent = create_agent()
      start = instruction(ChainOfThought.start_action(), %{prompt: "Test prompt", request_id: "req_cot_2"})
      {agent, [_spawn]} = ChainOfThought.cmd(agent, [start], %{})

      child_started =
        instruction(:cot_worker_child_started, %{
          parent_id: "parent",
          child_id: "child",
          child_module: Jido.AI.Reasoning.ChainOfThought.Worker.Agent,
          tag: :cot_worker,
          pid: self(),
          meta: %{}
        })

      {agent, directives} = ChainOfThought.cmd(agent, [child_started], %{})

      assert [%AgentDirective.Emit{} = emit] = directives
      assert emit.signal.type == "ai.cot.worker.start"
      assert emit.signal.data.request_id == "req_cot_2"
      assert emit.dispatch == {:pid, [target: self()]}

      state = StratState.get(agent, %{})
      assert state[:cot_worker_pid] == self()
      assert state[:cot_worker_status] == :running
      assert state[:pending_worker_start] == nil
    end

    test "request_completed worker event parses steps and conclusion" do
      agent = create_agent()

      events = [
        worker_event(:request_started, "req_cot_3", 1, %{query: "Compute"}),
        worker_event(:llm_started, "req_cot_3", 2, %{call_id: "cot_call_req_cot_3"}),
        worker_event(:llm_delta, "req_cot_3", 3, %{chunk_type: :content, delta: "Step 1: Start\n"}),
        worker_event(:llm_completed, "req_cot_3", 4, %{
          call_id: "cot_call_req_cot_3",
          text: "Step 1: Add.\nConclusion: 4",
          usage: %{input_tokens: 10, output_tokens: 5}
        }),
        worker_event(:request_completed, "req_cot_3", 5, %{
          result: "Step 1: Add.\nConclusion: 4",
          termination_reason: :success,
          usage: %{input_tokens: 10, output_tokens: 5}
        })
      ]

      {agent, []} =
        Enum.reduce(events, {agent, []}, fn event, {acc, _} ->
          ChainOfThought.cmd(acc, [instruction(:cot_worker_event, %{request_id: "req_cot_3", event: event})], %{})
        end)

      state = StratState.get(agent, %{})
      assert state[:status] == :completed
      assert state[:termination_reason] == :success
      assert state[:result] == "4"
      assert state[:conclusion] == "4"
      assert length(state[:steps]) == 1
      assert state[:usage] == %{input_tokens: 10, output_tokens: 5}
      assert state[:active_request_id] == nil
      assert state[:cot_worker_status] == :ready
    end

    test "request_failed worker event transitions to error state" do
      agent = create_agent()

      event =
        worker_event(:request_failed, "req_cot_4", 1, %{
          error: :rate_limited,
          error_type: :llm_request
        })

      {agent, []} =
        ChainOfThought.cmd(agent, [instruction(:cot_worker_event, %{request_id: "req_cot_4", event: event})], %{})

      state = StratState.get(agent, %{})
      assert state[:status] == :error
      assert state[:termination_reason] == :error
      assert state[:result] =~ "rate_limited"
      assert state[:active_request_id] == nil
    end

    test "worker crash while active request marks request failed" do
      agent = create_agent()

      state =
        agent
        |> StratState.get(%{})
        |> Map.put(:status, :reasoning)
        |> Map.put(:active_request_id, "req_cot_crash")
        |> Map.put(:cot_worker_pid, self())
        |> Map.put(:cot_worker_status, :running)

      agent = StratState.put(agent, state)

      crash =
        instruction(:cot_worker_child_exit, %{
          tag: :cot_worker,
          pid: self(),
          reason: :killed
        })

      {agent, []} = ChainOfThought.cmd(agent, [crash], %{})

      state = StratState.get(agent, %{})
      assert state[:status] == :error
      assert state[:active_request_id] == nil
      assert state[:cot_worker_status] == :missing
      assert state[:result] =~ "cot_worker_exit"
    end

    test "busy second request emits request error directive" do
      agent = create_agent()

      state =
        agent
        |> StratState.get(%{})
        |> Map.put(:status, :reasoning)
        |> Map.put(:active_request_id, "req_busy")

      agent = StratState.put(agent, state)

      {_agent, directives} =
        ChainOfThought.cmd(
          agent,
          [instruction(ChainOfThought.start_action(), %{prompt: "second", request_id: "req_busy_2"})],
          %{}
        )

      assert [%Directive.EmitRequestError{} = directive] = directives
      assert directive.request_id == "req_busy_2"
      assert directive.reason == :busy
    end

    test "stores request trace up to 2000 events then marks truncated" do
      agent = create_agent()
      request_id = "req_cot_trace"

      {agent, []} =
        Enum.reduce(1..2001, {agent, []}, fn seq, {acc, _} ->
          event = worker_event(:llm_delta, request_id, seq, %{chunk_type: :content, delta: "x"})
          ChainOfThought.cmd(acc, [instruction(:cot_worker_event, %{request_id: request_id, event: event})], %{})
        end)

      state = StratState.get(agent, %{})
      trace = state[:request_traces][request_id]
      assert trace.truncated? == true
      assert length(trace.events) == 2000
    end
  end

  describe "helper accessors" do
    test "get_steps/1 returns parsed steps" do
      agent = create_agent()
      state = StratState.get(agent, %{})
      state = Map.put(state, :steps, [%{number: 1, content: "first"}])
      agent = StratState.put(agent, state)

      assert ChainOfThought.get_steps(agent) == [%{number: 1, content: "first"}]
    end

    test "get_conclusion/1 returns conclusion" do
      agent = create_agent()
      state = StratState.get(agent, %{})
      state = Map.put(state, :conclusion, "answer")
      agent = StratState.put(agent, state)

      assert ChainOfThought.get_conclusion(agent) == "answer"
    end

    test "get_raw_response/1 returns raw response" do
      agent = create_agent()
      state = StratState.get(agent, %{})
      state = Map.put(state, :raw_response, "raw")
      agent = StratState.put(agent, state)

      assert ChainOfThought.get_raw_response(agent) == "raw"
    end
  end
end
