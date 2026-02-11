defmodule Jido.AI.Strategies.RLMParallelTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Strategies.RLM
  alias Jido.AI.RLM.WorkspaceStore

  defp create_agent(opts \\ []) do
    %Jido.Agent{
      id: "test-rlm-parallel-agent",
      name: "test_rlm_parallel",
      state: %{}
    }
    |> then(fn agent ->
      ctx = %{strategy_opts: opts}
      {agent, []} = RLM.init(agent, ctx)
      agent
    end)
  end

  defp run_cmd(agent, action, params) do
    instruction = %Jido.Instruction{action: action, params: params}
    RLM.cmd(agent, [instruction], %{})
  end

  defp create_multiline_context(line_count) do
    1..line_count
    |> Enum.map(fn i -> "Line #{i}: some data content here for testing purposes." end)
    |> Enum.join("\n")
  end

  describe "parallel_mode config" do
    test "defaults to :llm_driven" do
      agent = create_agent()
      state = StratState.get(agent, %{})
      assert state[:config][:parallel_mode] == :llm_driven
    end

    test "accepts :runtime mode" do
      agent = create_agent(parallel_mode: :runtime, max_depth: 1)
      state = StratState.get(agent, %{})
      assert state[:config][:parallel_mode] == :runtime
    end
  end

  describe "signal_routes" do
    test "includes rlm.fanout_complete route" do
      routes = RLM.signal_routes(%{})
      route_signals = Enum.map(routes, fn {signal, _} -> signal end)
      assert "rlm.fanout_complete" in route_signals
    end
  end

  describe "action_spec" do
    test "returns spec for fanout_complete action" do
      spec = RLM.action_spec(RLM.fanout_complete_action())
      assert spec.name == "rlm.fanout_complete"
    end
  end

  describe "start with parallel_mode: :runtime" do
    test "enters :preparing status and emits chunk directive" do
      agent = create_agent(parallel_mode: :runtime, max_depth: 1)
      context = create_multiline_context(100)

      {agent, directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "find something",
          context: context
        })

      state = StratState.get(agent, %{})
      assert state[:status] == :preparing
      assert state[:prepare][:phase] == :chunking
      assert is_binary(state[:prepare][:chunk_call_id])

      assert length(directives) == 1
      [directive] = directives
      assert %Jido.AI.Directive.ToolExec{} = directive
      assert directive.tool_name == "context_chunk"
      assert directive.action_module == Jido.AI.Actions.RLM.Context.Chunk
      assert directive.id == state[:prepare][:chunk_call_id]

      WorkspaceStore.delete(state[:workspace_ref])
    end

    test "does not enter prepare phase when max_depth is 0" do
      agent = create_agent(parallel_mode: :runtime, max_depth: 0)
      context = create_multiline_context(10)

      {agent, directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "find something",
          context: context
        })

      state = StratState.get(agent, %{})
      refute state[:status] == :preparing
      assert is_nil(state[:prepare])
      assert Enum.any?(directives, &match?(%Jido.AI.Directive.LLMStream{}, &1))
    end

    test "does not enter prepare phase when no context provided" do
      agent = create_agent(parallel_mode: :runtime, max_depth: 1)

      {agent, directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "find something"
        })

      state = StratState.get(agent, %{})
      refute state[:status] == :preparing
      assert is_nil(state[:prepare])
      assert Enum.any?(directives, &match?(%Jido.AI.Directive.LLMStream{}, &1))
    end
  end

  describe "prepare phase: chunk result handling" do
    test "transitions to spawning after chunk result" do
      agent = create_agent(parallel_mode: :runtime, max_depth: 1)
      context = create_multiline_context(100)

      {agent, _directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "find something",
          context: context
        })

      state = StratState.get(agent, %{})
      chunk_call_id = state[:prepare][:chunk_call_id]

      chunk_result = %{
        chunk_count: 3,
        chunks: [
          %{id: "c_0", lines: "1-34", preview: "Line 1:"},
          %{id: "c_1", lines: "35-67", preview: "Line 35:"},
          %{id: "c_2", lines: "68-100", preview: "Line 68:"}
        ]
      }

      {agent, directives} =
        run_cmd(agent, RLM.tool_result_action(), %{
          call_id: chunk_call_id,
          tool_name: "context_chunk",
          result: {:ok, chunk_result}
        })

      state = StratState.get(agent, %{})
      assert state[:status] == :preparing
      assert state[:prepare][:phase] == :spawning
      assert state[:prepare][:chunk_count] == 3
      assert is_binary(state[:prepare][:spawn_call_id])

      assert length(directives) == 1
      [directive] = directives
      assert %Jido.AI.Directive.ToolExec{} = directive
      assert directive.tool_name == "rlm_spawn_agent"
      assert directive.action_module == Jido.AI.Actions.RLM.Agent.Spawn
      assert directive.id == state[:prepare][:spawn_call_id]

      args = directive.arguments
      assert args["chunk_ids"] == ["c_0", "c_1", "c_2"]
      assert args["query"] == "find something"

      WorkspaceStore.delete(state[:workspace_ref])
    end

    test "falls back to ReAct when chunk result has no chunks" do
      agent = create_agent(parallel_mode: :runtime, max_depth: 1)
      context = create_multiline_context(10)

      {agent, _directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "find something",
          context: context
        })

      state = StratState.get(agent, %{})
      chunk_call_id = state[:prepare][:chunk_call_id]

      {agent, directives} =
        run_cmd(agent, RLM.tool_result_action(), %{
          call_id: chunk_call_id,
          tool_name: "context_chunk",
          result: {:ok, %{chunk_count: 0, chunks: []}}
        })

      state = StratState.get(agent, %{})
      refute state[:status] == :preparing
      assert is_nil(state[:prepare])
      assert Enum.any?(directives, &match?(%Jido.AI.Directive.LLMStream{}, &1))

      WorkspaceStore.delete(state[:workspace_ref])
    end
  end

  describe "prepare phase: spawn result handling" do
    setup do
      agent = create_agent(parallel_mode: :runtime, max_depth: 1)
      context = create_multiline_context(100)

      {agent, _} =
        run_cmd(agent, RLM.start_action(), %{
          query: "find budgets",
          context: context
        })

      state = StratState.get(agent, %{})
      chunk_call_id = state[:prepare][:chunk_call_id]

      chunk_result = %{
        chunk_count: 2,
        chunks: [
          %{id: "c_0", lines: "1-50", preview: "Line 1:"},
          %{id: "c_1", lines: "51-100", preview: "Line 51:"}
        ]
      }

      {agent, _} =
        run_cmd(agent, RLM.tool_result_action(), %{
          call_id: chunk_call_id,
          tool_name: "context_chunk",
          result: {:ok, chunk_result}
        })

      state = StratState.get(agent, %{})

      %{agent: agent, state: state}
    end

    test "transitions to synthesis after spawn result", %{agent: agent, state: state} do
      spawn_call_id = state[:prepare][:spawn_call_id]

      spawn_result = %{
        completed: 2,
        errors: 0,
        skipped: 0,
        results: [
          %{chunk_id: "c_0", answer: "Budget is $100", summary: "Budget is $100"},
          %{chunk_id: "c_1", answer: "No budget found", summary: "No budget found"}
        ]
      }

      {agent, directives} =
        run_cmd(agent, RLM.tool_result_action(), %{
          call_id: spawn_call_id,
          tool_name: "rlm_spawn_agent",
          result: {:ok, spawn_result}
        })

      state = StratState.get(agent, %{})
      assert state[:status] == :awaiting_llm
      assert is_nil(state[:prepare])

      config = state[:config]
      assert config[:max_iterations] == 1
      assert config[:reqllm_tools] == []
      assert config[:actions_by_name] == %{}

      assert Enum.any?(directives, &match?(%Jido.AI.Directive.LLMStream{}, &1))

      llm_directive = Enum.find(directives, &match?(%Jido.AI.Directive.LLMStream{}, &1))
      assert llm_directive.tools == []

      WorkspaceStore.delete(state[:workspace_ref])
    end

    test "handles spawn errors gracefully", %{agent: agent, state: state} do
      spawn_call_id = state[:prepare][:spawn_call_id]

      {agent, directives} =
        run_cmd(agent, RLM.tool_result_action(), %{
          call_id: spawn_call_id,
          tool_name: "rlm_spawn_agent",
          result: {:error, :spawn_failed}
        })

      state = StratState.get(agent, %{})
      assert state[:status] == :awaiting_llm
      assert Enum.any?(directives, &match?(%Jido.AI.Directive.LLMStream{}, &1))

      WorkspaceStore.delete(state[:workspace_ref])
    end
  end

  describe "busy rejection during prepare" do
    test "rejects new explore while preparing" do
      agent = create_agent(parallel_mode: :runtime, max_depth: 1)
      context = create_multiline_context(100)

      {agent, _} =
        run_cmd(agent, RLM.start_action(), %{
          query: "first query",
          context: context
        })

      state = StratState.get(agent, %{})
      assert state[:status] == :preparing

      {_agent, directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "second query",
          context: "more data"
        })

      assert [{:request_error, _call_id, :busy, message}] = directives
      assert message =~ "preparing"

      WorkspaceStore.delete(state[:workspace_ref])
    end
  end

  describe "fanout_complete signal" do
    test "transitions to synthesis" do
      agent = create_agent(parallel_mode: :runtime, max_depth: 1)
      context = create_multiline_context(100)

      {agent, _} =
        run_cmd(agent, RLM.start_action(), %{
          query: "find something",
          context: context
        })

      state = StratState.get(agent, %{})

      new_state =
        state
        |> Map.put(:status, :preparing)
        |> Map.put(:prepare, %{phase: :spawning})

      agent = StratState.put(agent, new_state)

      {agent, directives} =
        run_cmd(agent, RLM.fanout_complete_action(), %{
          chunk_count: 5,
          completed: 4,
          errors: 1
        })

      state = StratState.get(agent, %{})
      assert state[:status] == :awaiting_llm
      assert is_nil(state[:prepare])

      config = state[:config]
      assert config[:max_iterations] == 1
      assert config[:reqllm_tools] == []

      assert Enum.any?(directives, &match?(%Jido.AI.Directive.LLMStream{}, &1))

      WorkspaceStore.delete(state[:workspace_ref])
    end
  end

  describe "llm_driven mode (regression)" do
    test "starts normally without prepare phase" do
      agent = create_agent(parallel_mode: :llm_driven, max_depth: 1)
      context = create_multiline_context(10)

      {agent, directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "find something",
          context: context
        })

      state = StratState.get(agent, %{})
      refute state[:status] == :preparing
      assert is_nil(state[:prepare])
      assert Enum.any?(directives, &match?(%Jido.AI.Directive.LLMStream{}, &1))
    end

    test "default mode is llm_driven" do
      agent = create_agent(max_depth: 1)
      context = create_multiline_context(10)

      {agent, directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "find something",
          context: context
        })

      state = StratState.get(agent, %{})
      refute state[:status] == :preparing
      assert Enum.any?(directives, &match?(%Jido.AI.Directive.LLMStream{}, &1))
    end
  end

  describe "snapshot during prepare" do
    test "reports running status during prepare" do
      agent = create_agent(parallel_mode: :runtime, max_depth: 1)
      context = create_multiline_context(100)

      {agent, _} =
        run_cmd(agent, RLM.start_action(), %{
          query: "find something",
          context: context
        })

      snapshot = RLM.snapshot(agent, %{})
      assert snapshot.status == :running
      assert snapshot.done? == false

      state = StratState.get(agent, %{})
      WorkspaceStore.delete(state[:workspace_ref])
    end
  end

  describe "synthesis prompt" do
    test "builds correct synthesis prompt" do
      prompt =
        Jido.AI.RLM.Prompts.synthesis_prompt(%{
          original_query: "find all budgets",
          workspace_summary: "Chunk 0: Budget $100\nChunk 1: No budget",
          chunk_count: 2,
          completed: 2,
          errors: 0
        })

      assert prompt.role == :user
      assert prompt.content =~ "find all budgets"
      assert prompt.content =~ "2 parallel analyses"
      assert prompt.content =~ "Budget $100"
      refute prompt.content =~ "chunks failed"
    end

    test "includes error note when chunks fail" do
      prompt =
        Jido.AI.RLM.Prompts.synthesis_prompt(%{
          original_query: "query",
          workspace_summary: "results",
          chunk_count: 5,
          completed: 3,
          errors: 2
        })

      assert prompt.content =~ "2 chunks failed"
    end
  end
end
