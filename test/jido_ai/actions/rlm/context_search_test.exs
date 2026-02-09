defmodule JidoAITest.Actions.RLM.ContextSearchTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.RLM.Context.Search
  alias Jido.AI.RLM.{ContextStore, WorkspaceStore}

  setup do
    {:ok, workspace_ref} = WorkspaceStore.init("search-test-#{System.unique_integer()}")
    %{workspace_ref: workspace_ref}
  end

  describe "substring search" do
    test "finds exact matches", ctx do
      data = "Hello World, Hello Elixir"
      {:ok, context_ref} = ContextStore.put(data, "req-search-1")

      params = %{query: "Hello", mode: "substring"}
      context = %{context_ref: context_ref, workspace_ref: ctx.workspace_ref}

      {:ok, result} = Search.run(params, context)
      assert result.total_matches == 2
    end

    test "case-sensitive search misses different case", ctx do
      data = "Hello World, hello Elixir"
      {:ok, context_ref} = ContextStore.put(data, "req-search-2")

      params = %{query: "hello", mode: "substring", case_sensitive: true}
      context = %{context_ref: context_ref, workspace_ref: ctx.workspace_ref}

      {:ok, result} = Search.run(params, context)
      assert result.total_matches == 1
      assert hd(result.hits).offset == 13
    end

    test "case-insensitive search finds all cases", ctx do
      data = "Hello World, hello Elixir, HELLO BEAM"
      {:ok, context_ref} = ContextStore.put(data, "req-search-3")

      params = %{query: "hello", mode: "substring", case_sensitive: false}
      context = %{context_ref: context_ref, workspace_ref: ctx.workspace_ref}

      {:ok, result} = Search.run(params, context)
      assert result.total_matches == 3
    end
  end

  describe "regex search" do
    test "finds regex matches", ctx do
      data = "abc 123 def 456 ghi"
      {:ok, context_ref} = ContextStore.put(data, "req-search-4")

      params = %{query: "\\d+", mode: "regex"}
      context = %{context_ref: context_ref, workspace_ref: ctx.workspace_ref}

      {:ok, result} = Search.run(params, context)
      assert result.total_matches == 2
    end

    test "case-insensitive regex", ctx do
      data = "Foo bar FOO baz foo"
      {:ok, context_ref} = ContextStore.put(data, "req-search-5")

      params = %{query: "foo", mode: "regex", case_sensitive: false}
      context = %{context_ref: context_ref, workspace_ref: ctx.workspace_ref}

      {:ok, result} = Search.run(params, context)
      assert result.total_matches == 3
    end
  end

  describe "limit" do
    test "respects limit parameter", ctx do
      data = String.duplicate("needle ", 50)
      {:ok, context_ref} = ContextStore.put(data, "req-search-6")

      params = %{query: "needle", mode: "substring", limit: 5}
      context = %{context_ref: context_ref, workspace_ref: ctx.workspace_ref}

      {:ok, result} = Search.run(params, context)
      assert result.total_matches == 5
    end
  end

  describe "search history" do
    test "records search entries in workspace", ctx do
      data = "abc def ghi"
      {:ok, context_ref} = ContextStore.put(data, "req-search-7")
      context = %{context_ref: context_ref, workspace_ref: ctx.workspace_ref}

      Search.run(%{query: "abc"}, context)
      Search.run(%{query: "def"}, context)

      workspace = WorkspaceStore.get(ctx.workspace_ref)
      assert length(workspace.searches) == 2
      assert hd(workspace.searches).query == "def"
    end
  end

  describe "chunk_id resolution" do
    test "maps hits to chunk IDs when chunks are indexed", ctx do
      data = "aaaa\nbbbb\ncccc\ndddd\n"
      {:ok, context_ref} = ContextStore.put(data, "req-search-8")

      WorkspaceStore.update(ctx.workspace_ref, fn ws ->
        Map.put(ws, :chunks, %{
          index: %{
            "c_0" => %{byte_start: 0, byte_end: 10},
            "c_1" => %{byte_start: 10, byte_end: 20}
          }
        })
      end)

      params = %{query: "cccc", mode: "substring"}
      context = %{context_ref: context_ref, workspace_ref: ctx.workspace_ref}

      {:ok, result} = Search.run(params, context)
      assert result.total_matches == 1
      assert hd(result.hits).chunk_id == "c_1"
    end
  end
end
