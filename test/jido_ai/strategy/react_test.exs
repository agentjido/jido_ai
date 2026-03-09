defmodule Jido.AI.Reasoning.ReAct.StrategyTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive, as: AgentDirective
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Directive
  alias Jido.AI.Reasoning.ReAct.Strategy, as: ReAct
  alias Jido.Thread
  alias Jido.Thread.Agent, as: ThreadAgent

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

  defp context_replace_instruction(context, opts \\ []) do
    instruction(
      ReAct.context_modify_action(),
      %{
        op_id: Keyword.get(opts, :op_id, "op_#{Jido.Util.generate_id()}"),
        context_ref: Keyword.get(opts, :context_ref, "default"),
        operation: %{
          type: :replace,
          reason: Keyword.get(opts, :reason, :manual),
          result_context: context
        }
      }
    )
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

  describe "init validation" do
    test "raises for unsupported request_policy values" do
      assert_raise ArgumentError, ~r/unsupported request_policy/, fn ->
        create_agent(tools: [TestCalculator], request_policy: :queue)
      end
    end
  end

  describe "signal_routes/1" do
    test "routes delegated worker signals and compatibility observability signals" do
      routes = ReAct.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["ai.react.query"] == {:strategy_cmd, :ai_react_start}
      assert route_map["ai.react.set_system_prompt"] == {:strategy_cmd, :ai_react_set_system_prompt}
      refute Map.has_key?(route_map, "ai.react.set_context")
      assert route_map["ai.react.context.modify"] == {:strategy_cmd, :ai_react_context_modify}
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

    test "start payload context includes state snapshot key" do
      agent =
        create_agent(
          tools: [TestCalculator],
          tool_context: %{state: %{override: true}, tenant: "acme"}
        )
        |> then(fn agent -> %{agent | state: Map.put(agent.state, :custom_counter, 7)} end)

      start_instruction = instruction(ReAct.start_action(), %{query: "What is 2 + 2?", request_id: "req_ctx"})
      {agent, [_spawn]} = ReAct.cmd(agent, [start_instruction], %{})

      state = StratState.get(agent, %{})
      context = state.pending_worker_start.context

      assert is_map(context.state)
      assert context.state.custom_counter == 7
      assert context.state.__strategy__.status == :idle
      assert context.tenant == "acme"
      refute Map.has_key?(context.state, :override)
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

    test "start merges base and run llm_opts into runtime config" do
      agent =
        create_agent(
          tools: [TestCalculator],
          llm_opts: [thinking: %{type: :enabled, budget_tokens: 1_024}, reasoning_effort: :low]
        )

      start_instruction =
        instruction(ReAct.start_action(), %{
          query: "What is 2 + 2?",
          request_id: "req_1",
          llm_opts: [reasoning_effort: :high]
        })

      {agent, [_spawn]} = ReAct.cmd(agent, [start_instruction], %{})

      state = StratState.get(agent, %{})

      assert state.pending_worker_start.config.llm.llm_opts == [
               thinking: %{type: :enabled, budget_tokens: 1_024},
               reasoning_effort: :high
             ]
    end

    test "start accepts string-key llm_opts maps and normalizes ReqLLM options" do
      agent =
        create_agent(
          tools: [TestCalculator],
          llm_opts: %{
            "thinking" => %{type: :enabled, budget_tokens: 1_024},
            "reasoning_effort" => :low,
            "top_p" => 0.7
          }
        )

      start_instruction =
        instruction(ReAct.start_action(), %{
          query: "What is 2 + 2?",
          request_id: "req_1",
          llm_opts: %{"reasoning_effort" => :high, "top_p" => 0.9, "unknown_provider_flag" => true}
        })

      {agent, [_spawn]} = ReAct.cmd(agent, [start_instruction], %{})

      state = StratState.get(agent, %{})
      llm_opts = state.pending_worker_start.config.llm.llm_opts

      assert Keyword.get(llm_opts, :thinking) == %{type: :enabled, budget_tokens: 1_024}
      assert Keyword.get(llm_opts, :reasoning_effort) == :high
      assert Keyword.get(llm_opts, :top_p) == 0.9
      refute Keyword.has_key?(llm_opts, nil)
    end

    test "start maps existing-atom string llm_opts keys for provider options" do
      existing_key = :custom_provider_flag
      existing_key_string = Atom.to_string(existing_key)

      agent = create_agent(tools: [TestCalculator])

      start_instruction =
        instruction(ReAct.start_action(), %{
          query: "What is 2 + 2?",
          request_id: "req_1",
          llm_opts: %{existing_key_string => true}
        })

      {agent, [_spawn]} = ReAct.cmd(agent, [start_instruction], %{})

      state = StratState.get(agent, %{})
      llm_opts = state.pending_worker_start.config.llm.llm_opts

      assert Keyword.get(llm_opts, existing_key) == true
    end

    test "start drops non-existing string llm_opts keys and filters nil keys" do
      agent = create_agent(tools: [TestCalculator])

      start_instruction =
        instruction(ReAct.start_action(), %{
          query: "What is 2 + 2?",
          request_id: "req_1",
          llm_opts: %{"__jido_ai_nonexistent_llm_opt_key__" => true}
        })

      {agent, [_spawn]} = ReAct.cmd(agent, [start_instruction], %{})

      state = StratState.get(agent, %{})
      llm_opts = state.pending_worker_start.config.llm.llm_opts

      assert llm_opts == []
      refute Keyword.has_key?(llm_opts, nil)
    end

    test "start normalizes provider_options maps in llm_opts using provider schema keys" do
      agent = create_agent(tools: [TestCalculator], model: "openai:gpt-4o")

      start_instruction =
        instruction(ReAct.start_action(), %{
          query: "What is 2 + 2?",
          request_id: "req_1",
          llm_opts: %{
            "provider_options" => %{
              "verbosity" => "high",
              "__jido_ai_nonexistent_provider_option__" => true
            }
          }
        })

      {agent, [_spawn]} = ReAct.cmd(agent, [start_instruction], %{})

      state = StratState.get(agent, %{})
      llm_opts = state.pending_worker_start.config.llm.llm_opts
      provider_options = Keyword.get(llm_opts, :provider_options)

      assert provider_options == [verbosity: "high"]
      refute Keyword.has_key?(provider_options, nil)
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

    test "completed request history is reused for the next turn" do
      agent = create_agent(tools: [TestCalculator])

      {agent, [_spawn]} =
        ReAct.cmd(agent, [instruction(ReAct.start_action(), %{query: "Who am I?", request_id: "req_turn_1"})], %{})

      first_turn_events = [
        runtime_event(:request_started, "req_turn_1", 1, %{query: "Who am I?"}),
        runtime_event(:llm_completed, "req_turn_1", 2, %{
          turn_type: :final_answer,
          text: "You asked who you are.",
          thinking_content: nil,
          tool_calls: [],
          usage: %{}
        }),
        runtime_event(:request_completed, "req_turn_1", 3, %{
          result: "You asked who you are.",
          termination_reason: :final_answer,
          usage: %{}
        })
      ]

      {agent, []} =
        Enum.reduce(first_turn_events, {agent, []}, fn event, {acc, _} ->
          ReAct.cmd(acc, [instruction(:ai_react_worker_event, %{request_id: "req_turn_1", event: event})], %{})
        end)

      {agent, [_spawn]} =
        ReAct.cmd(
          agent,
          [instruction(ReAct.start_action(), %{query: "What did I just ask?", request_id: "req_turn_2"})],
          %{}
        )

      state = StratState.get(agent, %{})
      history = Jido.AI.Context.to_messages(state.pending_worker_start.state.context)
      history = Enum.reject(history, &(&1.role == :system))

      assert history == [
               %{role: :user, content: "Who am I?"},
               %{role: :assistant, content: "You asked who you are."},
               %{role: :user, content: "What did I just ask?"}
             ]
    end

    test "snapshot exposes conversation projected from thread state" do
      agent = create_agent(tools: [TestCalculator])

      {agent, [_spawn]} =
        ReAct.cmd(agent, [instruction(ReAct.start_action(), %{query: "Track this", request_id: "req_snap"})], %{})

      events = [
        runtime_event(:request_started, "req_snap", 1, %{query: "Track this"}),
        runtime_event(:llm_completed, "req_snap", 2, %{
          turn_type: :final_answer,
          text: "Tracked",
          thinking_content: nil,
          tool_calls: [],
          usage: %{}
        }),
        runtime_event(:request_completed, "req_snap", 3, %{
          result: "Tracked",
          termination_reason: :final_answer,
          usage: %{}
        })
      ]

      {agent, []} =
        Enum.reduce(events, {agent, []}, fn event, {acc, _} ->
          ReAct.cmd(acc, [instruction(:ai_react_worker_event, %{request_id: "req_snap", event: event})], %{})
        end)

      snapshot = ReAct.snapshot(agent, %{})
      conversation = Enum.reject(snapshot.details.conversation, &(&1.role == :system))

      assert conversation == [
               %{role: :user, content: "Track this"},
               %{role: :assistant, content: "Tracked"}
             ]
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
              req_http_options: [plug: {Req.Test, []}],
              llm_opts: [thinking: %{type: :enabled, budget_tokens: 256}]
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
      refute Map.has_key?(state, :run_llm_opts)
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

    test "context.modify replace updates base conversation context" do
      agent = create_agent(tools: [TestCalculator], system_prompt: "Original prompt")

      context =
        Jido.AI.Context.new(system_prompt: "Restored prompt")
        |> Jido.AI.Context.append_messages([
          %{role: :user, content: "Hello"},
          %{role: :assistant, content: "Hi there"}
        ])

      {agent, []} =
        ReAct.cmd(
          agent,
          [context_replace_instruction(context)],
          %{}
        )

      state = StratState.get(agent, %{})
      assert state.context == context
      assert state.config.system_prompt == "Restored prompt"

      messages = Jido.AI.Context.to_messages(state.context)
      non_system = Enum.reject(messages, &(&1.role == :system))

      assert non_system == [
               %{role: :user, content: "Hello"},
               %{role: :assistant, content: "Hi there"}
             ]
    end

    test "context.modify replace with nil system_prompt preserves existing config prompt" do
      agent = create_agent(tools: [TestCalculator], system_prompt: "Keep me")

      context =
        Jido.AI.Context.new()
        |> Jido.AI.Context.append_messages([%{role: :user, content: "test"}])

      {agent, []} =
        ReAct.cmd(
          agent,
          [context_replace_instruction(context)],
          %{}
        )

      {agent, [_spawn]} =
        ReAct.cmd(
          agent,
          [instruction(ReAct.start_action(), %{query: "next turn", request_id: "req_nil_prompt"})],
          %{}
        )

      state = StratState.get(agent, %{})
      assert state.context == context
      assert state.config.system_prompt == "Keep me"
      assert state.pending_worker_start.state.context.system_prompt == nil
    end

    test "context.modify replace while active run is deferred and applied after request completion" do
      agent = create_agent(tools: [TestCalculator], system_prompt: "Original prompt")

      {agent, [_spawn]} =
        ReAct.cmd(
          agent,
          [instruction(ReAct.start_action(), %{query: "Q1", request_id: "req_deferred_complete"})],
          %{}
        )

      replacement =
        Jido.AI.Context.new(system_prompt: "Restored prompt")
        |> Jido.AI.Context.append_messages([
          %{role: :user, content: "Restored user"},
          %{role: :assistant, content: "Restored assistant"}
        ])

      {agent, []} =
        ReAct.cmd(
          agent,
          [context_replace_instruction(replacement)],
          %{}
        )

      state = StratState.get(agent, %{})
      assert state.pending_context_op.operation.type == :replace
      assert state.pending_context_op.operation.result_context == replacement
      assert state.config.system_prompt == "Original prompt"

      completion_events = [
        runtime_event(:llm_completed, "req_deferred_complete", 2, %{
          turn_type: :final_answer,
          text: "A1",
          thinking_content: nil,
          tool_calls: [],
          usage: %{}
        }),
        runtime_event(:request_completed, "req_deferred_complete", 3, %{
          result: "A1",
          termination_reason: :final_answer,
          usage: %{}
        })
      ]

      {agent, []} =
        Enum.reduce(completion_events, {agent, []}, fn event, {acc, _} ->
          ReAct.cmd(
            acc,
            [instruction(:ai_react_worker_event, %{request_id: "req_deferred_complete", event: event})],
            %{}
          )
        end)

      state = StratState.get(agent, %{})
      assert state.context == replacement
      assert state.pending_context_op == nil
      assert state.config.system_prompt == "Restored prompt"

      core_thread = ThreadAgent.get(agent)
      ai_entries = Thread.filter_by_kind(core_thread, [:ai_message, :ai_context_operation])
      last_entry = List.last(ai_entries)
      assert last_entry.kind == :ai_context_operation
      assert last_entry.payload.operation.type == :replace
      assert last_entry.payload.operation.reason == :manual
    end

    test "context.modify replace while active run is deferred and applied after request failure" do
      agent = create_agent(tools: [TestCalculator], system_prompt: "Original prompt")

      {agent, [_spawn]} =
        ReAct.cmd(
          agent,
          [instruction(ReAct.start_action(), %{query: "Q1", request_id: "req_deferred_failed"})],
          %{}
        )

      replacement =
        Jido.AI.Context.new(system_prompt: "Recovered prompt")
        |> Jido.AI.Context.append_messages([%{role: :user, content: "Recovered history"}])

      {agent, []} =
        ReAct.cmd(
          agent,
          [context_replace_instruction(replacement)],
          %{}
        )

      failed_event =
        runtime_event(:request_failed, "req_deferred_failed", 2, %{
          error: {:runtime, :boom}
        })

      {agent, []} =
        ReAct.cmd(
          agent,
          [instruction(:ai_react_worker_event, %{request_id: "req_deferred_failed", event: failed_event})],
          %{}
        )

      state = StratState.get(agent, %{})
      assert state.context == replacement
      assert state.pending_context_op == nil
      assert state.config.system_prompt == "Recovered prompt"
    end

    test "context.modify replace while active run is deferred and applied after worker crash terminalization" do
      agent = create_agent(tools: [TestCalculator], system_prompt: "Original prompt")

      active_state =
        agent
        |> StratState.get(%{})
        |> Map.put(:status, :awaiting_tool)
        |> Map.put(:active_request_id, "req_deferred_crash")
        |> Map.put(:react_worker_pid, self())
        |> Map.put(:react_worker_status, :running)

      agent = StratState.put(agent, active_state)

      replacement =
        Jido.AI.Context.new(system_prompt: "Crash replacement")
        |> Jido.AI.Context.append_messages([%{role: :user, content: "Recovered after crash"}])

      {agent, []} =
        ReAct.cmd(
          agent,
          [context_replace_instruction(replacement)],
          %{}
        )

      crash_instruction =
        instruction(:ai_react_worker_child_exit, %{
          tag: :react_worker,
          pid: self(),
          reason: :killed
        })

      {agent, []} = ReAct.cmd(agent, [crash_instruction], %{})

      state = StratState.get(agent, %{})
      assert state.status == :error
      assert state.context == replacement
      assert state.pending_context_op == nil
      assert state.config.system_prompt == "Crash replacement"
    end

    test "context.modify replace with invalid params is a no-op" do
      agent = create_agent(tools: [TestCalculator], system_prompt: "Original")

      {agent, []} =
        ReAct.cmd(
          agent,
          [context_replace_instruction("not a context")],
          %{}
        )

      state = StratState.get(agent, %{})
      assert state.config.system_prompt == "Original"
      assert %Jido.AI.Context{} = state.context
    end

    test "context.modify replace applies immediately while idle and appends core thread operation event" do
      agent = create_agent(tools: [TestCalculator], system_prompt: "Original prompt")

      replacement =
        Jido.AI.Context.new(system_prompt: "Compacted prompt")
        |> Jido.AI.Context.append_messages([%{role: :user, content: "summary"}])

      {agent, []} =
        ReAct.cmd(
          agent,
          [
            instruction(ReAct.context_modify_action(), %{
              op_id: "op_compact",
              context_ref: "default",
              operation: %{
                type: :replace,
                reason: :compaction,
                result_context: replacement,
                meta: %{window: %{from: 1, to: 100}}
              }
            })
          ],
          %{}
        )

      state = StratState.get(agent, %{})
      assert state.context == replacement
      assert state.active_context_ref == "default"
      assert "op_compact" in state.applied_context_ops
      assert is_integer(state.projection_cursor_seq)

      core_thread = ThreadAgent.get(agent)
      [entry] = Thread.filter_by_kind(core_thread, :ai_context_operation)

      assert entry.payload.op_id == "op_compact"
      assert entry.payload.context_ref == "default"
      assert entry.payload.operation.type == :replace
      assert entry.payload.operation.reason == :compaction
    end

    test "context.modify deduplicates duplicate op_id" do
      agent = create_agent(tools: [TestCalculator], system_prompt: "Original prompt")

      replacement_a =
        Jido.AI.Context.new(system_prompt: "A")
        |> Jido.AI.Context.append_messages([%{role: :user, content: "A"}])

      replacement_b =
        Jido.AI.Context.new(system_prompt: "B")
        |> Jido.AI.Context.append_messages([%{role: :user, content: "B"}])

      modify = fn context ->
        instruction(ReAct.context_modify_action(), %{
          op_id: "op_dup",
          operation: %{type: :replace, reason: :manual, result_context: context}
        })
      end

      {agent, []} = ReAct.cmd(agent, [modify.(replacement_a)], %{})
      {agent, []} = ReAct.cmd(agent, [modify.(replacement_b)], %{})

      state = StratState.get(agent, %{})
      assert state.context == replacement_a

      core_thread = ThreadAgent.get(agent)
      assert length(Thread.filter_by_kind(core_thread, :ai_context_operation)) == 1
    end

    test "context.modify switch projects lane-specific context by context_ref" do
      agent = create_agent(tools: [TestCalculator], system_prompt: "Original prompt")

      alpha_context =
        Jido.AI.Context.new(system_prompt: "Alpha")
        |> Jido.AI.Context.append_messages([%{role: :user, content: "alpha"}])

      beta_context =
        Jido.AI.Context.new(system_prompt: "Beta")
        |> Jido.AI.Context.append_messages([%{role: :user, content: "beta"}])

      replace = fn ref, id, context ->
        instruction(ReAct.context_modify_action(), %{
          op_id: id,
          context_ref: ref,
          operation: %{type: :replace, reason: :manual, result_context: context}
        })
      end

      switch = fn ref, id ->
        instruction(ReAct.context_modify_action(), %{
          op_id: id,
          context_ref: ref,
          operation: %{type: :switch, reason: :manual}
        })
      end

      {agent, []} = ReAct.cmd(agent, [replace.("alpha", "op_alpha_replace", alpha_context)], %{})
      {agent, []} = ReAct.cmd(agent, [replace.("beta", "op_beta_replace", beta_context)], %{})
      {agent, []} = ReAct.cmd(agent, [switch.("alpha", "op_alpha_switch")], %{})

      state = StratState.get(agent, %{})
      assert state.active_context_ref == "alpha"
      assert state.context == alpha_context

      core_thread = ThreadAgent.get(agent)
      assert length(Thread.filter_by_kind(core_thread, :ai_context_operation)) == 3
    end

    test "context.modify switch to a fresh lane does not inherit previous lane history" do
      agent = create_agent(tools: [TestCalculator], system_prompt: "Original prompt")

      {agent, [_spawn]} =
        ReAct.cmd(
          agent,
          [instruction(ReAct.start_action(), %{query: "Q1", request_id: "req_switch_fresh_lane"})],
          %{}
        )

      events = [
        runtime_event(:llm_completed, "req_switch_fresh_lane", 2, %{
          turn_type: :final_answer,
          text: "A1",
          thinking_content: nil,
          tool_calls: [],
          usage: %{}
        }),
        runtime_event(:request_completed, "req_switch_fresh_lane", 3, %{
          result: "A1",
          termination_reason: :final_answer,
          usage: %{}
        })
      ]

      {agent, []} =
        Enum.reduce(events, {agent, []}, fn event, {acc, _} ->
          ReAct.cmd(
            acc,
            [instruction(:ai_react_worker_event, %{request_id: "req_switch_fresh_lane", event: event})],
            %{}
          )
        end)

      {agent, []} =
        ReAct.cmd(
          agent,
          [
            instruction(ReAct.context_modify_action(), %{
              op_id: "op_switch_alpha",
              context_ref: "alpha",
              operation: %{type: :switch, reason: :manual}
            })
          ],
          %{}
        )

      state = StratState.get(agent, %{})
      assert state.active_context_ref == "alpha"
      assert state.context.system_prompt == "Original prompt"

      projected_messages =
        state.context
        |> Jido.AI.Context.to_messages()
        |> Enum.reject(&(&1.role == :system))

      assert projected_messages == []
    end

    test "core thread appends ai_message entries for user assistant and tool turns" do
      agent = create_agent(tools: [TestCalculator], system_prompt: "Original prompt")

      {agent, [_spawn]} =
        ReAct.cmd(
          agent,
          [instruction(ReAct.start_action(), %{query: "calculate", request_id: "req_ai_message"})],
          %{}
        )

      events = [
        runtime_event(:llm_completed, "req_ai_message", 2, %{
          turn_type: :tool_calls,
          text: "",
          thinking_content: nil,
          tool_calls: [%{id: "tc_1", name: "calculator", arguments: %{operation: "add", a: 1, b: 2}}],
          usage: %{}
        }),
        runtime_event(:tool_completed, "req_ai_message", 3, %{
          tool_call_id: "tc_1",
          tool_name: "calculator",
          result: {:ok, %{result: 3}, []}
        }),
        runtime_event(:request_completed, "req_ai_message", 4, %{
          result: "3",
          termination_reason: :final_answer,
          usage: %{}
        })
      ]

      {agent, []} =
        Enum.reduce(events, {agent, []}, fn event, {acc, _} ->
          ReAct.cmd(acc, [instruction(:ai_react_worker_event, %{request_id: "req_ai_message", event: event})], %{})
        end)

      core_thread = ThreadAgent.get(agent)
      ai_messages = Thread.filter_by_kind(core_thread, :ai_message)

      assert Enum.map(ai_messages, fn entry -> entry.payload.role end) == [:user, :assistant, :tool]
      assert Enum.all?(ai_messages, fn entry -> entry.payload.context_ref == "default" end)
    end

    test "init with initial context from agent.state" do
      initial_context =
        Jido.AI.Context.new(system_prompt: "Restored")
        |> Jido.AI.Context.append_messages([
          %{role: :user, content: "Previous question"},
          %{role: :assistant, content: "Previous answer"}
        ])

      agent =
        %Jido.Agent{
          id: "test-agent",
          name: "test",
          state: %{context: initial_context}
        }
        |> then(fn agent ->
          ctx = %{strategy_opts: [tools: [TestCalculator]]}
          {agent, []} = ReAct.init(agent, ctx)
          agent
        end)

      state = StratState.get(agent, %{})
      assert state.context == initial_context

      messages = Jido.AI.Context.to_messages(state.context)
      non_system = Enum.reject(messages, &(&1.role == :system))

      assert non_system == [
               %{role: :user, content: "Previous question"},
               %{role: :assistant, content: "Previous answer"}
             ]
    end

    test "init with initial context without system_prompt gets config prompt" do
      initial_context =
        Jido.AI.Context.new()
        |> Jido.AI.Context.append_messages([
          %{role: :user, content: "Previous question"},
          %{role: :assistant, content: "Previous answer"}
        ])

      assert initial_context.system_prompt == nil

      agent =
        %Jido.Agent{
          id: "test-agent",
          name: "test",
          state: %{context: initial_context}
        }
        |> then(fn agent ->
          ctx = %{strategy_opts: [tools: [TestCalculator], system_prompt: "Config prompt"]}
          {agent, []} = ReAct.init(agent, ctx)
          agent
        end)

      state = StratState.get(agent, %{})
      assert state.context.system_prompt == "Config prompt"

      messages = Jido.AI.Context.to_messages(state.context)
      non_system = Enum.reject(messages, &(&1.role == :system))

      assert non_system == [
               %{role: :user, content: "Previous question"},
               %{role: :assistant, content: "Previous answer"}
             ]
    end

    test "init rejects legacy :thread context payloads" do
      legacy_context =
        Jido.AI.Context.new(system_prompt: "Legacy key")
        |> Jido.AI.Context.append_messages([%{role: :user, content: "legacy"}])

      agent = %Jido.Agent{id: "test-agent", name: "test", state: %{thread: legacy_context}}
      ctx = %{strategy_opts: [tools: [TestCalculator]]}

      assert_raise ArgumentError,
                   ~r/initial_state\[:thread\] is no longer supported for AI context/,
                   fn ->
                     ReAct.init(agent, ctx)
                   end
    end

    test "init ignores non-context :thread state from core thread plugins" do
      agent = %Jido.Agent{id: "test-agent", name: "test", state: %{thread: %{id: "thread_1", rev: 2}}}

      {agent, []} = ReAct.init(agent, %{strategy_opts: [tools: [TestCalculator]]})
      state = StratState.get(agent, %{})

      assert %Jido.AI.Context{} = state.context
      assert state.context.id != "thread_1"
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
