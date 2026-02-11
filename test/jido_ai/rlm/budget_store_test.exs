defmodule Jido.AI.RLM.BudgetStoreTest do
  use ExUnit.Case, async: true

  alias Jido.AI.RLM.BudgetStore

  describe "init/2" do
    test "defaults to no limits" do
      {:ok, ref} = BudgetStore.new("req-1", [])
      status = BudgetStore.status(ref)
      assert status.children_max == nil
      assert status.tokens_max == nil
      assert status.children_used == 0
      assert status.tokens_used == 0
    end

    test "accepts max_children_total" do
      {:ok, ref} = BudgetStore.new("req-2", max_children_total: 5)
      status = BudgetStore.status(ref)
      assert status.children_max == 5
      assert status.children_used == 0
    end

    test "accepts token_budget" do
      {:ok, ref} = BudgetStore.new("req-3", token_budget: 10_000)
      status = BudgetStore.status(ref)
      assert status.tokens_max == 10_000
      assert status.tokens_used == 0
    end
  end

  describe "reserve_children/2" do
    test "grants all when no limit" do
      {:ok, ref} = BudgetStore.new("req-10", [])
      assert {:ok, 5, :unlimited} = BudgetStore.reserve_children(ref, 5)
      assert {:ok, 100, :unlimited} = BudgetStore.reserve_children(ref, 100)
    end

    test "grants up to max when limited" do
      {:ok, ref} = BudgetStore.new("req-11", max_children_total: 3)
      assert {:ok, 3, 0} = BudgetStore.reserve_children(ref, 3)
    end

    test "grants partial when near limit" do
      {:ok, ref} = BudgetStore.new("req-12", max_children_total: 5)
      assert {:ok, 3, 2} = BudgetStore.reserve_children(ref, 3)
      assert {:ok, 2, 0} = BudgetStore.reserve_children(ref, 4)
    end

    test "grants 0 when exhausted" do
      {:ok, ref} = BudgetStore.new("req-13", max_children_total: 2)
      assert {:ok, 2, 0} = BudgetStore.reserve_children(ref, 2)
      assert {:ok, 0, 0} = BudgetStore.reserve_children(ref, 1)
    end

    test "concurrent reservations never exceed max" do
      {:ok, ref} = BudgetStore.new("req-14", max_children_total: 5)

      tasks =
        for _ <- 1..10 do
          Task.async(fn -> BudgetStore.reserve_children(ref, 1) end)
        end

      results = Task.await_many(tasks)
      total_granted = Enum.sum(for {:ok, granted, _} <- results, do: granted)
      assert total_granted == 5
    end
  end

  describe "add_tokens/2" do
    test "works with no limit" do
      {:ok, ref} = BudgetStore.new("req-20", [])
      assert :ok = BudgetStore.add_tokens(ref, 5000)
      assert :ok = BudgetStore.add_tokens(ref, 5000)
      assert BudgetStore.status(ref).tokens_used == 10_000
    end

    test "returns error when exceeded" do
      {:ok, ref} = BudgetStore.new("req-21", token_budget: 1000)
      assert :ok = BudgetStore.add_tokens(ref, 800)
      assert {:error, :token_budget_exceeded} = BudgetStore.add_tokens(ref, 300)
      assert BudgetStore.status(ref).tokens_used == 800
    end
  end

  describe "status/1" do
    test "returns correct counts" do
      {:ok, ref} = BudgetStore.new("req-30", max_children_total: 10, token_budget: 5000)
      BudgetStore.reserve_children(ref, 3)
      BudgetStore.add_tokens(ref, 1200)

      status = BudgetStore.status(ref)
      assert status.children_used == 3
      assert status.children_max == 10
      assert status.tokens_used == 1200
      assert status.tokens_max == 5000
    end
  end

  describe "destroy/1" do
    test "stops the GenServer" do
      {:ok, ref} = BudgetStore.new("req-40", [])
      assert Process.alive?(ref.pid)
      :ok = BudgetStore.destroy(ref)
      refute Process.alive?(ref.pid)
    end
  end
end
