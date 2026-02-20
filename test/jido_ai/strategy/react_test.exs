defmodule Jido.AI.Reasoning.ReAct.StrategyTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive, as: AgentDirective
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Directive
  alias Jido.AI.Reasoning.ReAct.Strategy, as: ReAct

  defmodule TestCalculator do
    use Jido.Action,
      name: "calculator",
      description: "A simple calculator"

    def run(%{operation: "add", a: a, b: b}, _ctx), do: {:ok, %{result: a + b}}
    def run(%{operation: "multiply", a: a, b: b}, _ctx), do: {:ok, %{result: a * b}}
  end

  defmodule TestSearch do
    use Jido.Action,
      name: "search",
      description: "Search for information"

    def run(%{query: query}, _ctx), do: {:ok, %{results: ["Found: #{query}"]}}
  end

  defp create_agent(opts) do
    %Jido.Agent{
      id: "test-agent",
      name: "test",
      state: %{}
    }
    |> then(fn agent ->
      ctx = %{strategy_opts: opts}
      {agent, []} = ReAct.init(agent, ctx)
      agent
    end)
  end

  defp instruction(action, params) do
    %Jido.Instruction{action: action, params: params}
  end

  defp runtime_event(kind, request_id, seq, data) do
    %{
      id: "evt_#{seq}",
      seq: seq,
      at_ms: 1_700_000_000_000 + seq,
      run_id: request_id,
      request_id: request_id,
      iteration: 1,
      kind: kind,
      llm_call_id: "call_#{request_id}",
      tool_call_id: nil,
      tool_name: nil,
      data: data
    }
  end

  describe "signal_routes/1" do
    test "routes delegated worker signals and compatibility observability signals" do
      routes = ReAct.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["ai.react.query"] == {:strategy_cmd, :ai_react_start}
      assert route_map["ai.react.set_system_prompt"] == {:strategy_cmd, :ai_react_set_system_prompt}
      assert route_map["ai.react.worker.event"] == {:strategy_cmd, :ai_react_worker_event}
      assert route_map["jido.agent.child.started"] == {:strategy_cmd, :ai_react_worker_child_started}
      assert route_map["jido.agent.child.exit"] == {:strategy_cmd, :ai_react_worker_child_exit}

      assert route_map["ai.llm.response"] == Jido.Actions.Control.Noop
      assert route_map["ai.tool.result"] == Jido.Actions.Control.Noop
      assert route_map["ai.llm.delta"] == Jido.Actions.Control.Noop
    end
  end

  describe "delegation lifecycle" do
    test "start lazily spawns worker and stores deferred start payload" do
      agent = create_agent(tools: [TestCalculator])

      start_instruction = instruction(ReAct.start_action(), %{query: "What is 2 + 2?", request_id: "req_1"})
      {agent, directives} = ReAct.cmd(agent, [start_instruction], %{})

      assert [%AgentDirective.SpawnAgent{} = spawn] = directives
      assert spawn.tag == :react_worker
      assert spawn.agent == Jido.AI.Reasoning.ReAct.Worker.Agent

      state = StratState.get(agent, %{})
      assert state.status == :awaiting_llm
      assert state.active_request_id == "req_1"
      assert state.react_worker_status == :starting
      assert is_map(state.pending_worker_start)
      assert state.pending_worker_start.request_id == "req_1"
      assert state.pending_worker_start.query == "What is 2 + 2?"
      assert state.pending_worker_start.config.streaming == true
    end

    test "start propagates streaming option into runtime config" do
      agent = create_agent(tools: [TestCalculator], streaming: false)

      start_instruction = instruction(ReAct.start_action(), %{query: "What is 2 + 2?", request_id: "req_1"})
      {agent, [_spawn]} = ReAct.cmd(agent, [start_instruction], %{})

      state = StratState.get(agent, %{})
      assert state.pending_worker_start.config.streaming == false
    end

    test "start merges base and run req_http_options into runtime config" do
      agent =
        create_agent(
          tools: [TestCalculator],
          req_http_options: [plug: {Req.Test, []}]
        )

      start_instruction =
        instruction(ReAct.start_action(), %{
          query: "What is 2 + 2?",
          request_id: "req_1",
          req_http_options: [adapter: [recv_timeout: 1234]]
        })

      {agent, [_spawn]} = ReAct.cmd(agent, [start_instruction], %{})

      state = StratState.get(agent, %{})

      assert state.pending_worker_start.config.llm.req_http_options == [
               plug: {Req.Test, []},
               adapter: [recv_timeout: 1234]
             ]
    end

    test "child started flushes deferred start to worker pid" do
      agent = create_agent(tools: [TestCalculator])

      {agent, _spawn_directives} =
        ReAct.cmd(agent, [instruction(ReAct.start_action(), %{query: "go", request_id: "req_child"})], %{})

      child_started =
        instruction(:ai_react_worker_child_started, %{
          parent_id: "parent",
          child_id: "child",
          child_module: Jido.AI.Reasoning.ReAct.Worker.Agent,
          tag: :react_worker,
          pid: self(),
          meta: %{}
        })

      {agent, directives} = ReAct.cmd(agent, [child_started], %{})

      assert [%AgentDirective.Emit{} = emit] = directives
      assert emit.signal.type == "ai.react.worker.start"
      assert emit.signal.data.request_id == "req_child"
      assert emit.dispatch == {:pid, [target: self()]}

      state = StratState.get(agent, %{})
      assert state.react_worker_pid == self()
      assert state.react_worker_status == :running
      assert state.pending_worker_start == nil
    end

    test "worker runtime event updates state and emits lifecycle signals" do
      agent = create_agent(tools: [TestCalculator])

      event = runtime_event(:request_started, "req_evt", 1, %{query: "hello"})

      {agent, []} =
        ReAct.cmd(agent, [instruction(:ai_react_worker_event, %{request_id: "req_evt", event: event})], %{})

      state = StratState.get(agent, %{})
      assert state.status == :awaiting_llm
      assert state.active_request_id == "req_evt"

      trace = state.request_traces["req_evt"]
      assert trace.truncated? == false
      assert length(trace.events) == 1
    end

    test "request_completed event marks request terminal and keeps checkpoint token" do
      agent = create_agent(tools: [TestCalculator])

      events = [
        runtime_event(:request_started, "req_done", 1, %{query: "q"}),
        runtime_event(:checkpoint, "req_done", 2, %{token: "tok_1", reason: :after_llm}),
        runtime_event(:request_completed, "req_done", 3, %{
          result: "done",
          termination_reason: :final_answer,
          usage: %{input_tokens: 10, output_tokens: 5}
        })
      ]

      {agent, []} =
        Enum.reduce(events, {agent, []}, fn event, {acc, _} ->
          ReAct.cmd(acc, [instruction(:ai_react_worker_event, %{request_id: "req_done", event: event})], %{})
        end)

      state = StratState.get(agent, %{})
      assert state.status == :completed
      assert state.active_request_id == nil
      assert state.result == "done"
      assert state.checkpoint_token == "tok_1"
      assert state.react_worker_status == :ready
    end

    test "request completion clears ephemeral req_http_options" do
      agent = create_agent(tools: [TestCalculator])

      {agent, [_spawn]} =
        ReAct.cmd(
          agent,
          [
            instruction(ReAct.start_action(), %{
              query: "q",
              request_id: "req_ephemeral",
              req_http_options: [plug: {Req.Test, []}]
            })
          ],
          %{}
        )

      event =
        runtime_event(:request_completed, "req_ephemeral", 2, %{
          result: "done",
          termination_reason: :final_answer,
          usage: %{}
        })

      {agent, []} =
        ReAct.cmd(
          agent,
          [instruction(:ai_react_worker_event, %{request_id: "req_ephemeral", event: event})],
          %{}
        )

      state = StratState.get(agent, %{})
      refute Map.has_key?(state, :run_req_http_options)
    end

    test "terminal checkpoint after request completion does not reopen active request" do
      agent = create_agent(tools: [TestCalculator])

      events = [
        runtime_event(:request_started, "req_terminal_checkpoint", 1, %{query: "q"}),
        runtime_event(:request_completed, "req_terminal_checkpoint", 2, %{
          result: "done",
          termination_reason: :final_answer,
          usage: %{}
        }),
        runtime_event(:checkpoint, "req_terminal_checkpoint", 3, %{token: "tok_terminal", reason: :terminal})
      ]

      {agent, []} =
        Enum.reduce(events, {agent, []}, fn event, {acc, _} ->
          ReAct.cmd(
            acc,
            [instruction(:ai_react_worker_event, %{request_id: "req_terminal_checkpoint", event: event})],
            %{}
          )
        end)

      state = StratState.get(agent, %{})
      assert state.status == :completed
      assert state.checkpoint_token == "tok_terminal"
      assert state.active_request_id == nil
    end

    test "cancel forwards worker cancel signal for active request" do
      agent = create_agent(tools: [TestCalculator])

      state =
        agent
        |> StratState.get(%{})
        |> Map.put(:status, :awaiting_llm)
        |> Map.put(:active_request_id, "req_cancel")
        |> Map.put(:react_worker_pid, self())
        |> Map.put(:react_worker_status, :running)

      agent = StratState.put(agent, state)

      cancel_instruction =
        instruction(ReAct.cancel_action(), %{request_id: "req_cancel", reason: :user_cancelled})

      {agent, directives} = ReAct.cmd(agent, [cancel_instruction], %{})

      assert [%AgentDirective.Emit{} = emit] = directives
      assert emit.signal.type == "ai.react.worker.cancel"
      assert emit.signal.data.request_id == "req_cancel"
      assert emit.signal.data.reason == :user_cancelled
      assert emit.dispatch == {:pid, [target: self()]}

      state = StratState.get(agent, %{})
      assert state.cancel_reason == :user_cancelled
    end

    test "worker crash while active request marks request failed" do
      agent = create_agent(tools: [TestCalculator])

      state =
        agent
        |> StratState.get(%{})
        |> Map.put(:status, :awaiting_tool)
        |> Map.put(:active_request_id, "req_crash")
        |> Map.put(:react_worker_pid, self())
        |> Map.put(:react_worker_status, :running)

      agent = StratState.put(agent, state)

      crash_instruction =
        instruction(:ai_react_worker_child_exit, %{
          tag: :react_worker,
          pid: self(),
          reason: :killed
        })

      {agent, []} = ReAct.cmd(agent, [crash_instruction], %{})

      state = StratState.get(agent, %{})
      assert state.status == :error
      assert state.active_request_id == nil
      assert state.react_worker_pid == nil
      assert state.react_worker_status == :missing
      assert state.result =~ "react_worker_exit"
    end

    test "stores request trace up to 2000 events then marks truncated" do
      agent = create_agent(tools: [TestCalculator])
      request_id = "req_trace"

      {agent, []} =
        Enum.reduce(1..2001, {agent, []}, fn seq, {acc, _} ->
          event = runtime_event(:llm_delta, request_id, seq, %{chunk_type: :content, delta: "x"})
          ReAct.cmd(acc, [instruction(:ai_react_worker_event, %{request_id: request_id, event: event})], %{})
        end)

      state = StratState.get(agent, %{})
      trace = state.request_traces[request_id]

      assert trace.truncated? == true
      assert length(trace.events) == 2000
    end
  end

  describe "tool configuration and compatibility" do
    test "register_tool adds tool to config and list_tools/1" do
      agent = create_agent(tools: [TestCalculator])
      assert ReAct.list_tools(agent) == [TestCalculator]

      {agent, []} =
        ReAct.cmd(agent, [instruction(ReAct.register_tool_action(), %{tool_module: TestSearch})], %{})

      tools = ReAct.list_tools(agent)
      assert TestCalculator in tools
      assert TestSearch in tools
    end

    test "unregister_tool removes tool from config" do
      agent = create_agent(tools: [TestCalculator, TestSearch])

      {agent, []} =
        ReAct.cmd(agent, [instruction(ReAct.unregister_tool_action(), %{tool_name: "search"})], %{})

      tools = ReAct.list_tools(agent)
      assert TestCalculator in tools
      refute TestSearch in tools
    end

    test "set_tool_context replaces base tool context" do
      agent = create_agent(tools: [TestCalculator], tool_context: %{tenant: "a", region: "us"})

      {agent, []} =
        ReAct.cmd(
          agent,
          [instruction(ReAct.set_tool_context_action(), %{tool_context: %{tenant: "b"}})],
          %{}
        )

      state = StratState.get(agent, %{})
      assert state.config.base_tool_context == %{tenant: "b"}
    end

    test "set_system_prompt replaces base system prompt" do
      agent = create_agent(tools: [TestCalculator], system_prompt: "Original prompt")

      {agent, []} =
        ReAct.cmd(
          agent,
          [instruction(ReAct.set_system_prompt_action(), %{system_prompt: "Updated prompt"})],
          %{}
        )

      state = StratState.get(agent, %{})
      assert state.config.system_prompt == "Updated prompt"
    end

    test "runtime_adapter flag remains true even when opt-out is requested" do
      agent = create_agent(tools: [TestCalculator], runtime_adapter: false)
      state = StratState.get(agent, %{})
      assert state.config.runtime_adapter == true
    end

    test "busy start emits request error directive" do
      agent = create_agent(tools: [TestCalculator])

      state =
        agent
        |> StratState.get(%{})
        |> Map.put(:status, :awaiting_llm)
        |> Map.put(:active_request_id, "req_busy")

      agent = StratState.put(agent, state)

      {_agent, directives} =
        ReAct.cmd(agent, [instruction(ReAct.start_action(), %{query: "second", request_id: "req_new"})], %{})

      assert [%Directive.EmitRequestError{} = directive] = directives
      assert directive.request_id == "req_new"
      assert directive.reason == :busy
    end
  end
end
