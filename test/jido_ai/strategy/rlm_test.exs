defmodule Jido.AI.Strategies.RLMTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Strategies.RLM
  alias Jido.AI.RLM.{ContextStore, WorkspaceStore}

  defp create_agent(opts \\ []) do
    %Jido.Agent{
      id: "test-rlm-agent",
      name: "test_rlm",
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

  describe "action_spec/1" do
    test "returns spec for start action" do
      spec = RLM.action_spec(RLM.start_action())
      assert spec.name == "rlm.start"
    end

    test "returns spec for workspace_create action" do
      spec = RLM.action_spec(RLM.workspace_create_action())
      assert spec.name == "rlm.workspace.create"
    end

    test "returns spec for workspace_delete action" do
      spec = RLM.action_spec(RLM.workspace_delete_action())
      assert spec.name == "rlm.workspace.delete"
    end

    test "returns spec for context_load action" do
      spec = RLM.action_spec(RLM.context_load_action())
      assert spec.name == "rlm.context.load"
    end

    test "returns spec for context_delete action" do
      spec = RLM.action_spec(RLM.context_delete_action())
      assert spec.name == "rlm.context.delete"
    end
  end

  describe "signal_routes/1" do
    test "includes lifecycle routes" do
      routes = RLM.signal_routes(%{})
      route_signals = Enum.map(routes, fn {signal, _} -> signal end)

      assert "rlm.workspace.create" in route_signals
      assert "rlm.workspace.delete" in route_signals
      assert "rlm.context.load" in route_signals
      assert "rlm.context.delete" in route_signals
    end

    test "includes exploration routes" do
      routes = RLM.signal_routes(%{})
      route_signals = Enum.map(routes, fn {signal, _} -> signal end)

      assert "rlm.explore" in route_signals
      assert "react.llm.response" in route_signals
      assert "react.tool.result" in route_signals
      assert "react.llm.delta" in route_signals
    end
  end

  describe "init/2" do
    test "initializes with default config" do
      agent = create_agent()
      state = StratState.get(agent, %{})
      config = state[:config]

      assert config[:model] == "anthropic:claude-sonnet-4-20250514"
      assert config[:recursive_model] == "anthropic:claude-haiku-4-5"
      assert config[:max_iterations] == 15
      assert config[:max_depth] == 0
    end

    test "initializes with custom config" do
      agent = create_agent(model: "openai:gpt-4o", max_iterations: 5, max_depth: 2)
      state = StratState.get(agent, %{})
      config = state[:config]

      assert config[:model] == "openai:gpt-4o"
      assert config[:max_iterations] == 5
      assert config[:max_depth] == 2
    end

    test "includes spawn tool when max_depth > 0" do
      agent = create_agent(max_depth: 2)
      state = StratState.get(agent, %{})
      config = state[:config]

      tool_names = Enum.map(config[:tools], & &1.name())
      assert "rlm_spawn_agent" in tool_names
    end

    test "excludes spawn tool when max_depth is 0" do
      agent = create_agent(max_depth: 0)
      state = StratState.get(agent, %{})
      config = state[:config]

      tool_names = Enum.map(config[:tools], & &1.name())
      refute "rlm_spawn_agent" in tool_names
    end
  end

  describe "workspace_create" do
    test "creates a workspace and stores ref in state" do
      agent = create_agent()
      {agent, directives} = run_cmd(agent, RLM.workspace_create_action(), %{})

      assert [{:workspace_created, workspace_ref}] = directives
      assert is_map(workspace_ref)
      assert is_pid(workspace_ref.pid)

      state = StratState.get(agent, %{})
      assert state[:workspace_ref] == workspace_ref

      WorkspaceStore.delete(workspace_ref)
    end

    test "creates workspace with seed data" do
      agent = create_agent()
      seed = %{custom_key: "initial_value"}
      {_agent, [{:workspace_created, workspace_ref}]} = run_cmd(agent, RLM.workspace_create_action(), %{seed: seed})

      workspace = WorkspaceStore.get(workspace_ref)
      assert workspace == seed

      WorkspaceStore.delete(workspace_ref)
    end

    test "creates workspace with empty default" do
      agent = create_agent()
      {_agent, [{:workspace_created, workspace_ref}]} = run_cmd(agent, RLM.workspace_create_action(), %{})

      workspace = WorkspaceStore.get(workspace_ref)
      assert workspace == %{}

      WorkspaceStore.delete(workspace_ref)
    end
  end

  describe "workspace_delete" do
    test "deletes workspace by ref in params" do
      agent = create_agent()

      {agent, [{:workspace_created, workspace_ref}]} =
        run_cmd(agent, RLM.workspace_create_action(), %{})

      assert WorkspaceStore.get(workspace_ref) == %{}

      {_agent, [{:workspace_deleted, ^workspace_ref}]} =
        run_cmd(agent, RLM.workspace_delete_action(), %{workspace_ref: workspace_ref})

      assert_raise ArgumentError, fn -> WorkspaceStore.get(workspace_ref) end
    end

    test "clears workspace_ref from state when deleting active workspace" do
      agent = create_agent()

      {agent, [{:workspace_created, workspace_ref}]} =
        run_cmd(agent, RLM.workspace_create_action(), %{})

      state = StratState.get(agent, %{})
      assert state[:workspace_ref] == workspace_ref

      {agent, _} = run_cmd(agent, RLM.workspace_delete_action(), %{workspace_ref: workspace_ref})

      state = StratState.get(agent, %{})
      assert state[:workspace_ref] == nil
    end

    test "returns empty directives when no workspace exists" do
      agent = create_agent()
      {_agent, directives} = run_cmd(agent, RLM.workspace_delete_action(), %{})
      assert directives == []
    end
  end

  describe "context_load" do
    test "loads binary context and returns ref" do
      agent = create_agent()
      context_data = "Hello, this is some context data for testing."

      {agent, [{:context_loaded, context_ref}]} =
        run_cmd(agent, RLM.context_load_action(), %{context: context_data})

      assert is_map(context_ref)
      assert {:ok, ^context_data} = ContextStore.fetch(context_ref)

      state = StratState.get(agent, %{})
      assert state[:context_ref] == context_ref

      ContextStore.delete(context_ref)
    end

    test "loads small context as inline" do
      agent = create_agent()
      context_data = "small"

      {_agent, [{:context_loaded, context_ref}]} =
        run_cmd(agent, RLM.context_load_action(), %{context: context_data})

      assert context_ref.backend == :inline
    end

    test "loads context with workspace ref for co-located storage" do
      agent = create_agent()

      {agent, [{:workspace_created, workspace_ref}]} =
        run_cmd(agent, RLM.workspace_create_action(), %{})

      large_data = String.duplicate("x", 3_000_000)

      {_agent, [{:context_loaded, context_ref}]} =
        run_cmd(agent, RLM.context_load_action(), %{
          context: large_data,
          workspace_ref: workspace_ref
        })

      assert context_ref.backend == :workspace
      assert {:ok, ^large_data} = ContextStore.fetch(context_ref)

      ContextStore.delete(context_ref)
      WorkspaceStore.delete(workspace_ref)
    end
  end

  describe "context_delete" do
    test "deletes context by ref" do
      agent = create_agent()
      context_data = String.duplicate("x", 3_000_000)

      {agent, [{:context_loaded, context_ref}]} =
        run_cmd(agent, RLM.context_load_action(), %{context: context_data})

      assert {:ok, _} = ContextStore.fetch(context_ref)

      {_agent, [{:context_deleted, ^context_ref}]} =
        run_cmd(agent, RLM.context_delete_action(), %{context_ref: context_ref})

      assert {:error, :not_found} = ContextStore.fetch(context_ref)
    end

    test "clears context_ref from state when deleting active context" do
      agent = create_agent()
      context_data = "some data"

      {agent, [{:context_loaded, context_ref}]} =
        run_cmd(agent, RLM.context_load_action(), %{context: context_data})

      state = StratState.get(agent, %{})
      assert state[:context_ref] == context_ref

      {agent, _} = run_cmd(agent, RLM.context_delete_action(), %{context_ref: context_ref})

      state = StratState.get(agent, %{})
      assert state[:context_ref] == nil
    end

    test "returns empty directives when no context exists" do
      agent = create_agent()
      {_agent, directives} = run_cmd(agent, RLM.context_delete_action(), %{})
      assert directives == []
    end
  end

  describe "rlm_start with pre-existing refs" do
    test "accepts pre-existing workspace_ref" do
      agent = create_agent()

      {:ok, workspace_ref} = WorkspaceStore.init("external-ws")

      {agent, _directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "test query",
          context: "test context",
          workspace_ref: workspace_ref
        })

      state = StratState.get(agent, %{})
      assert state[:workspace_ref] == workspace_ref
      assert state[:owns_workspace] == false
      assert state[:owns_context] == true
    end

    test "accepts pre-existing context_ref" do
      agent = create_agent()

      {:ok, context_ref} = ContextStore.put("pre-loaded data", "ext-ctx")

      {agent, _directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "test query",
          context_ref: context_ref
        })

      state = StratState.get(agent, %{})
      assert state[:context_ref] == context_ref
      assert state[:owns_context] == false
      assert state[:owns_workspace] == true
    end

    test "accepts both pre-existing refs" do
      {:ok, workspace_ref} = WorkspaceStore.init("ext-ws-2")
      {:ok, context_ref} = ContextStore.put("pre-loaded", "ext-ctx-2")

      agent = create_agent()

      {agent, _directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "test",
          workspace_ref: workspace_ref,
          context_ref: context_ref
        })

      state = StratState.get(agent, %{})
      assert state[:owns_workspace] == false
      assert state[:owns_context] == false

      WorkspaceStore.delete(workspace_ref)
      ContextStore.delete(context_ref)
    end

    test "creates own refs when none provided" do
      agent = create_agent()

      {agent, _directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "test",
          context: "some data"
        })

      state = StratState.get(agent, %{})
      assert state[:owns_workspace] == true
      assert state[:owns_context] == true
    end
  end

  describe "snapshot/2" do
    test "includes workspace_ref and context_ref in details" do
      agent = create_agent()

      {agent, [{:workspace_created, workspace_ref}]} =
        run_cmd(agent, RLM.workspace_create_action(), %{})

      {agent, [{:context_loaded, context_ref}]} =
        run_cmd(agent, RLM.context_load_action(), %{context: "snapshot test data"})

      snapshot = RLM.snapshot(agent, %{})
      assert snapshot.details[:workspace_ref] == workspace_ref
      assert snapshot.details[:context_ref] == context_ref

      ContextStore.delete(context_ref)
      WorkspaceStore.delete(workspace_ref)
    end

    test "idle status for fresh agent" do
      agent = create_agent()
      snapshot = RLM.snapshot(agent, %{})

      assert snapshot.status == :idle
      assert snapshot.done? == false
    end
  end

  describe "multi-turn lifecycle" do
    test "workspace persists across create → load → start flow" do
      agent = create_agent()

      {agent, [{:workspace_created, workspace_ref}]} =
        run_cmd(agent, RLM.workspace_create_action(), %{})

      WorkspaceStore.update(workspace_ref, fn ws ->
        Map.put(ws, :notes, [%{kind: "finding", text: "pre-loaded note"}])
      end)

      {agent, [{:context_loaded, context_ref}]} =
        run_cmd(agent, RLM.context_load_action(), %{context: "exploration data"})

      {agent, _directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "find something",
          workspace_ref: workspace_ref,
          context_ref: context_ref
        })

      state = StratState.get(agent, %{})
      assert state[:workspace_ref] == workspace_ref
      assert state[:context_ref] == context_ref

      workspace = WorkspaceStore.get(workspace_ref)
      assert [%{text: "pre-loaded note"}] = workspace.notes

      ContextStore.delete(context_ref)
      WorkspaceStore.delete(workspace_ref)
    end

    test "workspace survives after explore completes with external refs" do
      {:ok, workspace_ref} = WorkspaceStore.init("persist-test")
      {:ok, context_ref} = ContextStore.put("some context", "persist-ctx")

      agent = create_agent()

      {agent, _directives} =
        run_cmd(agent, RLM.start_action(), %{
          query: "test query",
          workspace_ref: workspace_ref,
          context_ref: context_ref
        })

      state = StratState.get(agent, %{})
      assert state[:owns_workspace] == false
      assert state[:owns_context] == false

      assert WorkspaceStore.get(workspace_ref) == %{}
      assert {:ok, "some context"} = ContextStore.fetch(context_ref)

      WorkspaceStore.delete(workspace_ref)
      ContextStore.delete(context_ref)
    end
  end
end
