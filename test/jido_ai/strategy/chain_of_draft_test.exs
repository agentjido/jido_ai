defmodule Jido.AI.Reasoning.ChainOfDraft.StrategyTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive, as: AgentDirective
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Directive
  alias Jido.AI.Reasoning.ChainOfDraft
  alias Jido.AI.Reasoning.ChainOfDraft.Strategy, as: ChainOfDraftStrategy

  defp create_agent(opts \\ []) do
    %Jido.Agent{
      id: "test-agent",
      name: "test",
      state: %{}
    }
    |> then(fn agent ->
      ctx = %{strategy_opts: opts}
      {agent, []} = ChainOfDraftStrategy.init(agent, ctx)
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
      llm_call_id: "cod_call_#{request_id}",
      tool_call_id: nil,
      tool_name: nil,
      data: data
    }
  end

  describe "init/2" do
    test "uses Chain-of-Draft default prompt" do
      agent = create_agent()
      state = StratState.get(agent, %{})

      assert state[:config].system_prompt == ChainOfDraft.default_system_prompt()
    end
  end

  describe "signal_routes/1" do
    test "routes ai.cod.query and delegated worker events" do
      routes = ChainOfDraftStrategy.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["ai.cod.query"] == {:strategy_cmd, :cod_start}
      assert route_map["ai.cot.worker.event"] == {:strategy_cmd, :cod_worker_event}
      assert route_map["jido.agent.child.started"] == {:strategy_cmd, :cod_worker_child_started}
      assert route_map["jido.agent.child.exit"] == {:strategy_cmd, :cod_worker_child_exit}
      assert route_map["ai.request.error"] == {:strategy_cmd, :cod_request_error}
    end
  end

  describe "cmd/3" do
    test "cod_start emits CoT worker spawn directive" do
      agent = create_agent()
      start = instruction(:cod_start, %{prompt: "Solve quickly", request_id: "req_cod_1"})

      {agent, directives} = ChainOfDraftStrategy.cmd(agent, [start], %{})

      assert [%AgentDirective.SpawnAgent{} = spawn] = directives
      assert spawn.tag == :cot_worker
      assert spawn.agent == Jido.AI.Reasoning.ChainOfThought.Worker.Agent

      state = StratState.get(agent, %{})
      assert state[:status] == :reasoning
      assert state[:active_request_id] == "req_cod_1"
    end

    test "request_completed event extracts #### final answer" do
      agent = create_agent()

      events = [
        worker_event(:request_started, "req_cod_2", 1, %{query: "Jason had 20 ..."}),
        worker_event(:llm_completed, "req_cod_2", 2, %{
          call_id: "cod_call_req_cod_2",
          text: "20 - x = 12; x = 8. #### 8",
          usage: %{input_tokens: 10, output_tokens: 4}
        }),
        worker_event(:request_completed, "req_cod_2", 3, %{
          result: "20 - x = 12; x = 8. #### 8",
          termination_reason: :success,
          usage: %{input_tokens: 10, output_tokens: 4}
        })
      ]

      {agent, []} =
        Enum.reduce(events, {agent, []}, fn event, {acc, _dirs} ->
          ChainOfDraftStrategy.cmd(
            acc,
            [instruction(:cod_worker_event, %{request_id: "req_cod_2", event: event})],
            %{}
          )
        end)

      state = StratState.get(agent, %{})
      assert state[:status] == :completed
      assert state[:result] == "8"
      assert state[:conclusion] == "8"
    end

    test "request_failed worker event transitions to error state" do
      agent = create_agent()

      event =
        worker_event(:request_failed, "req_cod_3", 1, %{
          error: :rate_limited,
          error_type: :llm_request
        })

      {agent, []} =
        ChainOfDraftStrategy.cmd(agent, [instruction(:cod_worker_event, %{request_id: "req_cod_3", event: event})], %{})

      state = StratState.get(agent, %{})
      assert state[:status] == :error
      assert state[:termination_reason] == :error
      assert state[:result] =~ "rate_limited"
      assert state[:active_request_id] == nil
    end

    test "busy second request emits request error directive" do
      agent = create_agent()

      busy_state =
        agent
        |> StratState.get(%{})
        |> Map.put(:status, :reasoning)
        |> Map.put(:active_request_id, "req_cod_busy")

      agent = StratState.put(agent, busy_state)

      {_agent, directives} =
        ChainOfDraftStrategy.cmd(
          agent,
          [instruction(:cod_start, %{prompt: "second", request_id: "req_cod_busy_2"})],
          %{}
        )

      assert [%Directive.EmitRequestError{} = directive] = directives
      assert directive.request_id == "req_cod_busy_2"
      assert directive.reason == :busy
    end
  end
end
