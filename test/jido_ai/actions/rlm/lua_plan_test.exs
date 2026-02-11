defmodule JidoAITest.Actions.RLM.LuaPlanTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.RLM.Orchestrate.LuaPlan
  alias Jido.AI.RLM.{ChunkProjection, ContextStore, WorkspaceStore}

  setup do
    context_data = """
    Line 1: authentication module
    Line 2: login handler
    Line 3: password validation
    Line 4: session management
    Line 5: error handling
    Line 6: logging utilities
    """

    {:ok, context_ref} = ContextStore.put(context_data, "lua-plan-#{System.unique_integer()}")
    {:ok, workspace_ref} = WorkspaceStore.init("lua-plan-#{System.unique_integer()}")
    {:ok, _projection, _chunks} = ChunkProjection.create(workspace_ref, context_ref, %{strategy: "lines", size: 2}, %{})

    context = %{
      context_ref: context_ref,
      workspace_ref: workspace_ref,
      query: "Find the auth flow",
      current_depth: 0,
      max_depth: 2
    }

    %{context: context, workspace_ref: workspace_ref}
  end

  describe "plan validation (execute: false)" do
    test "simple plan selecting all chunks", %{context: ctx} do
      code = ~S"""
      local plan = {}
      for i = 1, #chunks do
        plan[#plan+1] = { chunk_ids = {chunks[i].id}, query = query }
      end
      return plan
      """

      params = %{code: code, execute: false}
      assert {:ok, result} = LuaPlan.run(params, ctx)
      assert result.executed == false
      assert length(result.plan) >= 3

      Enum.each(result.plan, fn item ->
        assert item.query == "Find the auth flow"
        assert length(item.chunk_ids) == 1
      end)
    end

    test "plan with custom queries per chunk", %{context: ctx} do
      code = ~S"""
      return {
        { chunk_ids = {"c_0"}, query = "analyze authentication" },
        { chunk_ids = {"c_2"}, query = "analyze error handling" }
      }
      """

      params = %{code: code, execute: false}
      assert {:ok, result} = LuaPlan.run(params, ctx)
      assert length(result.plan) == 2
      assert Enum.at(result.plan, 0).query == "analyze authentication"
      assert Enum.at(result.plan, 1).query == "analyze error handling"
    end

    test "plan grouping multiple chunks", %{context: ctx} do
      code = ~S"""
      return {
        { chunk_ids = {"c_0", "c_1"}, query = "analyze auth + validation" }
      }
      """

      params = %{code: code, execute: false}
      assert {:ok, result} = LuaPlan.run(params, ctx)
      assert length(result.plan) == 1
      assert result.plan |> hd() |> Map.get(:chunk_ids) == ["c_0", "c_1"]
    end

    test "plan uses default query when omitted", %{context: ctx} do
      code = ~S"""
      return { { chunk_ids = {"c_0"} } }
      """

      params = %{code: code, execute: false}
      assert {:ok, result} = LuaPlan.run(params, ctx)
      assert hd(result.plan).query == "Find the auth flow"
    end

    test "lua can read chunk_count", %{context: ctx} do
      code = ~S"""
      local plan = {}
      if chunk_count > 2 then
        plan[1] = { chunk_ids = {"c_0"}, query = "more than 2 chunks" }
      end
      return plan
      """

      params = %{code: code, execute: false}
      assert {:ok, result} = LuaPlan.run(params, ctx)
      assert length(result.plan) == 1
      assert hd(result.plan).query == "more than 2 chunks"
    end

    test "lua can read budget globals", %{context: ctx} do
      code = ~S"""
      local plan = {}
      local max = budget.max_total_chunks
      for i = 1, math.min(#chunks, max) do
        plan[#plan+1] = { chunk_ids = {chunks[i].id}, query = query }
      end
      return plan
      """

      params = %{code: code, execute: false, max_total_chunks: 2}
      assert {:ok, result} = LuaPlan.run(params, ctx)
      assert length(result.plan) == 2
    end
  end

  describe "budget enforcement" do
    test "rejects plan exceeding max_plan_items", %{context: ctx} do
      code = ~S"""
      return {
        { chunk_ids = {"c_0"}, query = "q1" },
        { chunk_ids = {"c_1"}, query = "q2" },
        { chunk_ids = {"c_2"}, query = "q3" }
      }
      """

      params = %{code: code, execute: false, max_plan_items: 2}
      assert {:error, msg} = LuaPlan.run(params, ctx)
      assert msg =~ "max is 2"
    end

    test "rejects plan exceeding max_total_chunks", %{context: ctx} do
      code = ~S"""
      return {
        { chunk_ids = {"c_0", "c_1", "c_2"}, query = "all" }
      }
      """

      params = %{code: code, execute: false, max_total_chunks: 2}
      assert {:error, msg} = LuaPlan.run(params, ctx)
      assert msg =~ "max is 2"
    end

    test "rejects unknown chunk_ids", %{context: ctx} do
      code = ~S"""
      return { { chunk_ids = {"c_99"}, query = "nope" } }
      """

      params = %{code: code, execute: false}
      assert {:error, msg} = LuaPlan.run(params, ctx)
      assert msg =~ "unknown chunk_ids"
    end
  end

  describe "Lua error handling" do
    test "reports compile errors", %{context: ctx} do
      params = %{code: "return {{{", execute: false}
      assert {:error, msg} = LuaPlan.run(params, ctx)
      assert msg =~ "Lua execution failed"
    end

    test "reports runtime errors", %{context: ctx} do
      params = %{code: "error('boom')", execute: false}
      assert {:error, msg} = LuaPlan.run(params, ctx)
      assert msg =~ "Lua execution failed"
    end

    test "rejects non-table return", %{context: ctx} do
      params = %{code: "return 42", execute: false}
      assert {:error, msg} = LuaPlan.run(params, ctx)
      assert msg =~ "plan must be a table"
    end

    test "enforces timeout on infinite loop", %{context: ctx} do
      params = %{code: "while true do end", execute: false, timeout_ms: 50}
      assert {:error, msg} = LuaPlan.run(params, ctx)
      assert msg =~ "Lua execution failed"
    end
  end

  describe "schema" do
    test "generates valid tool definition" do
      tool = LuaPlan.to_tool()
      assert tool.name == "rlm_lua_plan"
      assert tool.description =~ "Lua"

      properties = tool.parameters_schema.properties
      assert Map.has_key?(properties, :code)
    end

    test "code is required" do
      schema = LuaPlan.__action_metadata__().schema
      assert {:error, _} = Zoi.parse(schema, %{})
    end

    test "defaults are applied" do
      schema = LuaPlan.__action_metadata__().schema
      assert {:ok, validated} = Zoi.parse(schema, %{code: "return {}"})
      assert validated.execute == true
      assert validated.max_plan_items == 10
      assert validated.max_total_chunks == 30
      assert validated.timeout_ms == 500
    end
  end
end
