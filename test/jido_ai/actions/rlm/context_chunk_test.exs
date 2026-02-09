defmodule JidoAITest.Actions.RLM.ContextChunkTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.RLM.Context.Chunk
  alias Jido.AI.RLM.{ContextStore, WorkspaceStore}

  setup do
    {:ok, workspace_ref} = WorkspaceStore.init("chunk-test-#{System.unique_integer()}")

    %{workspace_ref: workspace_ref}
  end

  describe "line-based chunking" do
    test "chunks cover entire context without gaps", ctx do
      lines = Enum.map(1..25, &"Line #{&1}")
      data = Enum.join(lines, "\n")
      {:ok, context_ref} = ContextStore.put(data, "req-chunk-1")

      params = %{strategy: "lines", size: 10, overlap: 0}
      context = %{context_ref: context_ref, workspace_ref: ctx.workspace_ref}

      {:ok, result} = Chunk.run(params, context)
      assert result.chunk_count == 3

      workspace = WorkspaceStore.get(ctx.workspace_ref)
      index = workspace.chunks.index

      byte_ranges =
        index
        |> Enum.map(fn {_id, meta} -> {meta.byte_start, meta.byte_end} end)
        |> Enum.sort()

      {first_start, _} = hd(byte_ranges)
      assert first_start == 0

      {_, last_end} = List.last(byte_ranges)
      assert last_end == byte_size(data)

      byte_ranges
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [{_, end1}, {start2, _}] ->
        assert end1 == start2
      end)
    end

    test "includes trailing partial chunk", ctx do
      lines = Enum.map(1..7, &"Line #{&1}")
      data = Enum.join(lines, "\n")
      {:ok, context_ref} = ContextStore.put(data, "req-chunk-2")

      params = %{strategy: "lines", size: 3, overlap: 0}
      context = %{context_ref: context_ref, workspace_ref: ctx.workspace_ref}

      {:ok, result} = Chunk.run(params, context)
      assert result.chunk_count == 3
    end

    test "single line context produces one chunk", ctx do
      data = "single line no newline"
      {:ok, context_ref} = ContextStore.put(data, "req-chunk-3")

      params = %{strategy: "lines", size: 10, overlap: 0}
      context = %{context_ref: context_ref, workspace_ref: ctx.workspace_ref}

      {:ok, result} = Chunk.run(params, context)
      assert result.chunk_count == 1

      workspace = WorkspaceStore.get(ctx.workspace_ref)
      chunk = workspace.chunks.index["c_0"]
      assert chunk.byte_start == 0
      assert chunk.byte_end == byte_size(data)
    end

    test "overlap produces overlapping chunks", ctx do
      lines = Enum.map(1..10, &"Line #{&1}")
      data = Enum.join(lines, "\n")
      {:ok, context_ref} = ContextStore.put(data, "req-chunk-4")

      params = %{strategy: "lines", size: 5, overlap: 2}
      context = %{context_ref: context_ref, workspace_ref: ctx.workspace_ref}

      {:ok, result} = Chunk.run(params, context)
      assert result.chunk_count >= 3
    end

    test "chunk boundaries align with actual byte offsets", ctx do
      data = "abc\ndef\nghi\njkl"
      {:ok, context_ref} = ContextStore.put(data, "req-chunk-5")

      params = %{strategy: "lines", size: 2, overlap: 0}
      context = %{context_ref: context_ref, workspace_ref: ctx.workspace_ref}

      {:ok, _result} = Chunk.run(params, context)

      workspace = WorkspaceStore.get(ctx.workspace_ref)
      index = workspace.chunks.index

      c0 = index["c_0"]
      assert binary_part(data, c0.byte_start, c0.byte_end - c0.byte_start) == "abc\ndef\n"

      c1 = index["c_1"]
      assert binary_part(data, c1.byte_start, c1.byte_end - c1.byte_start) == "ghi\njkl"
    end
  end

  describe "byte-based chunking" do
    test "produces correct chunks", ctx do
      data = String.duplicate("x", 100)
      {:ok, context_ref} = ContextStore.put(data, "req-chunk-b1")

      params = %{strategy: "bytes", size: 30, overlap: 0}
      context = %{context_ref: context_ref, workspace_ref: ctx.workspace_ref}

      {:ok, result} = Chunk.run(params, context)
      assert result.chunk_count == 4
    end
  end
end
