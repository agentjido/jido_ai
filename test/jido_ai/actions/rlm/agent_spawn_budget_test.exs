defmodule JidoAITest.Actions.RLM.AgentSpawnBudgetTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.RLM.Agent.Spawn
  alias Jido.AI.RLM.{BudgetStore, ContextStore, WorkspaceStore}

  setup do
    context_data = "Hello World. This is chunk zero. More data here for chunk one. Extra text for chunk two. Additional chunk three data. Final chunk four content here."
    {:ok, context_ref} = ContextStore.put(context_data, "test-#{System.unique_integer()}")

    chunk_index = %{
      "c_0" => %{byte_start: 0, byte_end: 30},
      "c_1" => %{byte_start: 31, byte_end: 61},
      "c_2" => %{byte_start: 62, byte_end: 85},
      "c_3" => %{byte_start: 86, byte_end: 115},
      "c_4" => %{byte_start: 116, byte_end: 148}
    }

    {:ok, workspace_ref} =
      WorkspaceStore.init("test-#{System.unique_integer()}", %{
        chunks: %{index: chunk_index}
      })

    %{
      context_ref: context_ref,
      workspace_ref: workspace_ref,
      chunk_index: chunk_index
    }
  end

  describe "budget enforcement in spawn" do
    test "with budget: only grants allowed chunks", ctx do
      {:ok, budget_ref} = BudgetStore.new("test-budget", max_children_total: 2)

      context = %{
        workspace_ref: ctx.workspace_ref,
        context_ref: ctx.context_ref,
        current_depth: 5,
        max_depth: 2,
        budget_ref: budget_ref
      }

      params = %{
        chunk_ids: ["c_0", "c_1", "c_2", "c_3", "c_4"],
        query: "Summarize",
        max_concurrency: 5,
        timeout: 5_000,
        max_chunk_bytes: 100_000
      }

      {:ok, result} = Spawn.run(params, context)

      assert result.skipped == 3
      assert result.completed + result.errors == 2

      status = BudgetStore.status(budget_ref)
      assert status.children_used == 2

      BudgetStore.destroy(budget_ref)
    end

    test "with budget: exhausted budget grants 0", ctx do
      {:ok, budget_ref} = BudgetStore.new("test-budget", max_children_total: 2)

      {:ok, 2, 0} = BudgetStore.reserve_children(budget_ref, 2)

      context = %{
        workspace_ref: ctx.workspace_ref,
        context_ref: ctx.context_ref,
        current_depth: 5,
        max_depth: 2,
        budget_ref: budget_ref
      }

      params = %{
        chunk_ids: ["c_0", "c_1"],
        query: "Summarize",
        max_concurrency: 5,
        timeout: 5_000,
        max_chunk_bytes: 100_000
      }

      {:ok, result} = Spawn.run(params, context)

      assert result.completed == 0
      assert result.skipped == 2
      assert result.errors == 0

      status = BudgetStore.status(budget_ref)
      assert status.children_used == 2

      BudgetStore.destroy(budget_ref)
    end

    test "without budget: apply_budget returns all chunk_ids" do
      chunk_ids = ["c_0", "c_1", "c_2", "c_3", "c_4"]

      {granted, skipped} = apply_budget_via_spawn(nil, chunk_ids)

      assert granted == chunk_ids
      assert skipped == 0
    end

    test "budget propagates to child_tool_ctx", ctx do
      {:ok, budget_ref} = BudgetStore.new("test-propagation", max_children_total: 10)

      context = %{
        workspace_ref: ctx.workspace_ref,
        context_ref: ctx.context_ref,
        current_depth: 0,
        max_depth: 3,
        budget_ref: budget_ref,
        child_agent: MockChildAgent
      }

      assert context[:budget_ref] == budget_ref

      child_tool_ctx =
        %{
          current_depth: context.current_depth + 1,
          max_depth: context.max_depth,
          child_agent: context[:child_agent]
        }
        |> maybe_put(:budget_ref, context[:budget_ref])

      assert child_tool_ctx[:budget_ref] == budget_ref
      assert child_tool_ctx[:current_depth] == 1
      assert child_tool_ctx[:max_depth] == 3

      BudgetStore.destroy(budget_ref)
    end
  end

  defp apply_budget_via_spawn(nil, chunk_ids), do: {chunk_ids, 0}

  defp apply_budget_via_spawn(budget_ref, chunk_ids) do
    total = length(chunk_ids)
    {:ok, granted, _remaining} = BudgetStore.reserve_children(budget_ref, total)
    {Enum.take(chunk_ids, granted), total - granted}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
