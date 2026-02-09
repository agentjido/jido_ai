defmodule Jido.AI.Actions.RLM.ContextTest do
  use ExUnit.Case, async: true

  alias Jido.AI.RLM.ContextStore
  alias Jido.AI.RLM.WorkspaceStore
  alias Jido.AI.Actions.RLM.Context.Stats
  alias Jido.AI.Actions.RLM.Context.Chunk
  alias Jido.AI.Actions.RLM.Context.ReadChunk
  alias Jido.AI.Actions.RLM.Context.Search

  @test_context """
  Line 1: The quick brown fox
  Line 2: jumps over the lazy dog
  Line 3: The magic number is 42
  Line 4: More text here
  Line 5: Another line of content
  """

  setup do
    {:ok, context_ref} = ContextStore.put(@test_context, "test_req_1", ets_threshold: 10_000_000)
    {:ok, workspace_ref} = WorkspaceStore.init("test_req_1")

    context = %{context_ref: context_ref, workspace_ref: workspace_ref}

    %{context: context, context_ref: context_ref, workspace_ref: workspace_ref}
  end

  describe "Stats" do
    test "has correct metadata" do
      metadata = Stats.__action_metadata__()
      assert metadata.name == "context_stats"
      assert metadata.category == "rlm"
    end

    test "returns size_bytes, approx_lines, and sample", %{context: context} do
      {:ok, result} = Stats.run(%{}, context)

      assert result.size_bytes == byte_size(@test_context)
      assert result.approx_lines > 0
      assert is_binary(result.sample)
      assert byte_size(result.sample) <= 500
    end

    test "sample contains beginning of context", %{context: context} do
      {:ok, result} = Stats.run(%{}, context)

      assert String.starts_with?(result.sample, "Line 1:")
    end

    test "estimates reasonable line count", %{context: context} do
      {:ok, result} = Stats.run(%{}, context)

      assert result.approx_lines >= 5
      assert result.approx_lines <= 10
    end
  end

  describe "Chunk" do
    test "has correct metadata" do
      metadata = Chunk.__action_metadata__()
      assert metadata.name == "context_chunk"
      assert metadata.category == "rlm"
    end

    test "creates line-based chunks", %{context: context} do
      {:ok, result} = Chunk.run(%{strategy: "lines", size: 2, overlap: 0}, context)

      assert result.chunk_count > 0
      assert length(result.chunks) == result.chunk_count

      first = hd(result.chunks)
      assert first.id == "c_0"
      assert first.lines == "1-2"
      assert is_binary(first.preview)
    end

    test "creates byte-based chunks", %{context: context} do
      {:ok, result} = Chunk.run(%{strategy: "bytes", size: 50, overlap: 0}, context)

      assert result.chunk_count > 0

      first = hd(result.chunks)
      assert first.id == "c_0"
      assert is_binary(first.preview)
    end

    test "stores chunk index in workspace", %{context: context, workspace_ref: workspace_ref} do
      {:ok, _result} = Chunk.run(%{strategy: "lines", size: 2, overlap: 0}, context)

      workspace = WorkspaceStore.get(workspace_ref)
      assert workspace.chunks.strategy == "lines"
      assert workspace.chunks.size == 2
      assert is_map(workspace.chunks.index)
      assert Map.has_key?(workspace.chunks.index, "c_0")

      chunk_info = workspace.chunks.index["c_0"]
      assert is_integer(chunk_info.byte_start)
      assert is_integer(chunk_info.byte_end)
      assert is_binary(chunk_info.lines)
    end

    test "respects max_chunks", %{context: context} do
      {:ok, result} = Chunk.run(%{strategy: "lines", size: 1, max_chunks: 2}, context)

      assert result.chunk_count == 2
    end

    test "supports overlap", %{context: context} do
      {:ok, result} = Chunk.run(%{strategy: "lines", size: 3, overlap: 1}, context)

      assert result.chunk_count > 1
    end
  end

  describe "ReadChunk" do
    test "has correct metadata" do
      metadata = ReadChunk.__action_metadata__()
      assert metadata.name == "context_read_chunk"
      assert metadata.category == "rlm"
    end

    test "reads correct text for a chunk", %{context: context} do
      {:ok, _} = Chunk.run(%{strategy: "lines", size: 2, overlap: 0}, context)

      {:ok, result} = ReadChunk.run(%{chunk_id: "c_0"}, context)

      assert result.chunk_id == "c_0"
      assert is_binary(result.text)
      assert String.contains?(result.text, "Line 1:")
      assert result.truncated == false
      assert is_integer(result.byte_start)
      assert is_integer(result.byte_end)
    end

    test "returns error for missing chunk_id", %{context: context} do
      {:ok, _} = Chunk.run(%{strategy: "lines", size: 2, overlap: 0}, context)

      assert {:error, "chunk not found: c_999"} = ReadChunk.run(%{chunk_id: "c_999"}, context)
    end

    test "returns error when no chunks indexed", %{context: context} do
      assert {:error, "no chunks indexed" <> _} = ReadChunk.run(%{chunk_id: "c_0"}, context)
    end

    test "truncates when max_bytes is smaller than chunk", %{context: context} do
      {:ok, _} = Chunk.run(%{strategy: "lines", size: 3, overlap: 0}, context)

      {:ok, result} = ReadChunk.run(%{chunk_id: "c_0", max_bytes: 10}, context)

      assert result.truncated == true
      assert byte_size(result.text) == 10
    end
  end

  describe "Search" do
    test "has correct metadata" do
      metadata = Search.__action_metadata__()
      assert metadata.name == "context_search"
      assert metadata.category == "rlm"
    end

    test "finds substring matches", %{context: context} do
      {:ok, result} = Search.run(%{query: "Line"}, context)

      assert result.total_matches == 5
      assert length(result.hits) == 5

      first_hit = hd(result.hits)
      assert is_integer(first_hit.offset)
      assert is_binary(first_hit.snippet)
    end

    test "returns snippets with surrounding context", %{context: context} do
      {:ok, result} = Search.run(%{query: "magic number", window_bytes: 100}, context)

      assert result.total_matches == 1

      hit = hd(result.hits)
      assert String.contains?(hit.snippet, "magic number")
    end

    test "maps hits to chunk_ids when chunks are indexed", %{context: context} do
      {:ok, _} = Chunk.run(%{strategy: "lines", size: 2, overlap: 0}, context)
      {:ok, result} = Search.run(%{query: "magic number"}, context)

      assert result.total_matches == 1

      hit = hd(result.hits)
      assert hit.chunk_id != nil
    end

    test "returns nil chunk_id when no chunks indexed", %{context: context} do
      {:ok, result} = Search.run(%{query: "magic number"}, context)

      hit = hd(result.hits)
      assert hit.chunk_id == nil
    end

    test "respects limit", %{context: context} do
      {:ok, result} = Search.run(%{query: "Line", limit: 2}, context)

      assert result.total_matches == 5
      assert length(result.hits) == 2
    end

    test "supports regex mode", %{context: context} do
      {:ok, result} = Search.run(%{query: "\\d+", mode: "regex"}, context)

      assert result.total_matches > 0
    end

    test "returns error for invalid regex", %{context: context} do
      assert {:error, "invalid regex:" <> _} = Search.run(%{query: "[invalid", mode: "regex"}, context)
    end

    test "stores hits in workspace", %{context: context, workspace_ref: workspace_ref} do
      {:ok, _} = Search.run(%{query: "magic"}, context)

      workspace = WorkspaceStore.get(workspace_ref)
      assert is_list(workspace.hits)
      assert length(workspace.hits) > 0
    end
  end
end
