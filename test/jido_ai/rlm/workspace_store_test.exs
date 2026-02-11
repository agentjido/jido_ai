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

    test "creates workspace with adapter-managed table" do
      {:ok, ref} = WorkspaceStore.init("req-3")
      assert is_reference(ref.table)
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
          projections: %{
            chunks: %{
              "proj-1" => %{
                id: "proj-1",
                chunk_count: 100,
                spec: %{strategy: "lines", size: 1000},
                index: %{}
              }
            }
          },
          active_projections: %{chunks: "proj-1"}
        })

      summary = WorkspaceStore.summary(ref)
      assert summary =~ "Chunks: 100 indexed"
      assert summary =~ "lines"
      assert summary =~ "size 1000"
      assert summary =~ "projection proj-1"
    end

    test "workspace with multiple chunk projections" do
      {:ok, ref} =
        WorkspaceStore.init("req-8", %{
          projections: %{
            chunks: %{
              "proj-a" => %{id: "proj-a", chunk_count: 2, spec: %{strategy: "lines", size: 500}, index: %{}},
              "proj-b" => %{id: "proj-b", chunk_count: 4, spec: %{strategy: "bytes", size: 300}, index: %{}}
            }
          }
        })

      summary = WorkspaceStore.summary(ref)
      assert summary =~ "Chunks: 2 projections available"
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

    test "workspace with subquery_results" do
      {:ok, ref} =
        WorkspaceStore.init("req-11", %{
          subquery_results: [
            %{query: "q1", status: :ok},
            %{query: "q2", status: :ok},
            %{query: "q3", status: :pending}
          ]
        })

      summary = WorkspaceStore.summary(ref)
      assert summary =~ "Subquery results: 2 completed"
    end

    test "workspace with spawn_results" do
      {:ok, ref} =
        WorkspaceStore.init("req-11b", %{
          spawn_results: [
            %{agent: "a1", status: :ok},
            %{agent: "a2", status: :ok},
            %{agent: "a3", status: :error}
          ]
        })

      summary = WorkspaceStore.summary(ref)
      assert summary =~ "Spawn results: 2 completed"
    end

    test "full workspace summary" do
      {:ok, ref} =
        WorkspaceStore.init("req-12", %{
          projections: %{
            chunks: %{
              "proj-full" => %{
                id: "proj-full",
                chunk_count: 100,
                spec: %{strategy: "lines", size: 1000},
                index: %{}
              }
            }
          },
          active_projections: %{chunks: "proj-full"},
          hits: ["a", "b", "c"],
          notes: [%{type: "hypothesis", text: "h1"}, %{type: "finding", text: "f1"}],
          subquery_results: [
            %{query: "q1", status: :ok},
            %{query: "q2", status: :ok},
            %{query: "q3", status: :ok},
            %{query: "q4", status: :ok},
            %{query: "q5", status: :ok}
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
          projections: %{
            chunks: %{
              "proj-long" => %{
                id: "proj-long",
                chunk_count: 100,
                spec: %{strategy: "lines", size: 1000},
                index: %{}
              }
            }
          },
          active_projections: %{chunks: "proj-long"},
          hits: List.duplicate("hit", 100),
          notes: List.duplicate(%{type: "finding", text: "note"}, 50),
          subquery_results: List.duplicate(%{query: "q", status: :ok}, 200)
        })

      summary = WorkspaceStore.summary(ref, max_chars: 50)
      assert byte_size(summary) <= 50
      assert String.ends_with?(summary, "...")
    end
  end

  describe "delete/1" do
    test "delete destroys the workspace" do
      {:ok, ref} = WorkspaceStore.init("req-14", %{data: "important"})
      assert WorkspaceStore.get(ref) == %{data: "important"}
      :ok = WorkspaceStore.delete(ref)
      assert_raise ArgumentError, fn -> WorkspaceStore.get(ref) end
    end
  end
end
