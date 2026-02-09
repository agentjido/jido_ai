defmodule Jido.AI.RLM.WorkspaceStoreTest do
  use ExUnit.Case, async: true

  alias Jido.AI.RLM.WorkspaceStore

  describe "init/get cycle" do
    test "creates workspace with empty default" do
      {:ok, ref} = WorkspaceStore.init("req-1")
      assert WorkspaceStore.get(ref) == %{}
    end

    test "creates workspace with seed data" do
      seed = %{query: "find bugs", depth: 3}
      {:ok, ref} = WorkspaceStore.init("req-2", seed)
      assert WorkspaceStore.get(ref) == seed
    end

    test "accepts existing ETS table" do
      table = :ets.new(:custom, [:set, :private])
      {:ok, ref} = WorkspaceStore.init("req-3", %{}, table: table)
      assert ref.table == table
      assert WorkspaceStore.get(ref) == %{}
    end
  end

  describe "update/2" do
    test "modifies workspace state" do
      {:ok, ref} = WorkspaceStore.init("req-4")
      :ok = WorkspaceStore.update(ref, &Map.put(&1, :counter, 1))
      assert WorkspaceStore.get(ref) == %{counter: 1}
    end

    test "accumulates multiple updates" do
      {:ok, ref} = WorkspaceStore.init("req-5", %{items: []})

      :ok = WorkspaceStore.update(ref, fn ws -> Map.update!(ws, :items, &["a" | &1]) end)
      :ok = WorkspaceStore.update(ref, fn ws -> Map.update!(ws, :items, &["b" | &1]) end)

      assert WorkspaceStore.get(ref) == %{items: ["b", "a"]}
    end
  end

  describe "summary/2" do
    test "empty workspace returns empty string" do
      {:ok, ref} = WorkspaceStore.init("req-6")
      assert WorkspaceStore.summary(ref) == ""
    end

    test "workspace with chunks" do
      {:ok, ref} =
        WorkspaceStore.init("req-7", %{
          chunks: %{count: 100, type: "lines", size: 1000}
        })

      summary = WorkspaceStore.summary(ref)
      assert summary =~ "Chunks: 100 indexed"
      assert summary =~ "lines"
      assert summary =~ "size 1000"
    end

    test "workspace with chunk list" do
      {:ok, ref} =
        WorkspaceStore.init("req-8", %{
          chunks: [%{size: 500}, %{size: 300}]
        })

      summary = WorkspaceStore.summary(ref)
      assert summary =~ "Chunks: 2 indexed"
      assert summary =~ "size 800"
    end

    test "workspace with hits" do
      {:ok, ref} =
        WorkspaceStore.init("req-9", %{
          hits: ["match1", "match2", "match3"]
        })

      summary = WorkspaceStore.summary(ref)
      assert summary =~ "Hits: 3 found"
    end

    test "workspace with typed notes" do
      {:ok, ref} =
        WorkspaceStore.init("req-10", %{
          notes: [
            %{type: "hypothesis", text: "might be X"},
            %{type: "finding", text: "confirmed Y"}
          ]
        })

      summary = WorkspaceStore.summary(ref)
      assert summary =~ "Notes: 2"
      assert summary =~ "1 hypothesis"
      assert summary =~ "1 finding"
    end

    test "workspace with subqueries" do
      {:ok, ref} =
        WorkspaceStore.init("req-11", %{
          subqueries: [
            %{query: "q1", status: :completed},
            %{query: "q2", status: :completed},
            %{query: "q3", status: :pending}
          ]
        })

      summary = WorkspaceStore.summary(ref)
      assert summary =~ "Subquery results: 2 completed"
    end

    test "full workspace summary" do
      {:ok, ref} =
        WorkspaceStore.init("req-12", %{
          chunks: %{count: 100, type: "lines", size: 1000},
          hits: ["a", "b", "c"],
          notes: [%{type: "hypothesis", text: "h1"}, %{type: "finding", text: "f1"}],
          subqueries: [
            %{query: "q1", status: :completed},
            %{query: "q2", status: :completed},
            %{query: "q3", status: :completed},
            %{query: "q4", status: :completed},
            %{query: "q5", status: :completed}
          ]
        })

      summary = WorkspaceStore.summary(ref)
      assert summary =~ "Chunks:"
      assert summary =~ "Hits: 3 found"
      assert summary =~ "Notes: 2"
      assert summary =~ "Subquery results: 5 completed"
    end

    test "respects max_chars option" do
      {:ok, ref} =
        WorkspaceStore.init("req-13", %{
          chunks: %{count: 100, type: "lines", size: 1000},
          hits: List.duplicate("hit", 100),
          notes: List.duplicate(%{type: "finding", text: "note"}, 50),
          subqueries: List.duplicate(%{query: "q", status: :completed}, 200)
        })

      summary = WorkspaceStore.summary(ref, max_chars: 50)
      assert byte_size(summary) <= 50
      assert String.ends_with?(summary, "...")
    end
  end

  describe "delete/1" do
    test "delete then get returns empty map" do
      {:ok, ref} = WorkspaceStore.init("req-14", %{data: "important"})
      :ok = WorkspaceStore.delete(ref)
      assert WorkspaceStore.get(ref) == %{}
    end
  end
end
