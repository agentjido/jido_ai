defmodule Jido.AI.Actions.RLM.Context.Chunk do
  @moduledoc """
  Split context into chunks and index them for exploration.

  Supports line-based and byte-based chunking strategies with configurable
  overlap. Stores the chunk index in the workspace for use by ReadChunk
  and Search actions.

  ## Parameters

  * `strategy` - Chunking strategy: `"lines"` or `"bytes"` (default: `"lines"`)
  * `size` - Lines per chunk or bytes per chunk (default: `1000`)
  * `overlap` - Overlap in lines or bytes between chunks (default: `0`)
  * `max_chunks` - Maximum number of chunks to create (default: `500`)
  * `preview_bytes` - Bytes to include in each chunk preview (default: `100`)

  ## Returns

      %{
        chunk_count: 5,
        chunks: [%{id: "c_0", lines: "1-1000", preview: "first 100 bytes..."}]
      }
  """

  use Jido.Action,
    name: "context_chunk",
    description: "Split context into chunks and index them for exploration",
    category: "rlm",
    tags: ["rlm", "context", "chunking"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        strategy:
          Zoi.enum(["lines", "bytes"], description: "Chunking strategy")
          |> Zoi.default("lines"),
        size:
          Zoi.integer(description: "Lines per chunk or bytes per chunk")
          |> Zoi.default(1000),
        overlap:
          Zoi.integer(description: "Overlap in lines or bytes between chunks")
          |> Zoi.default(0),
        max_chunks:
          Zoi.integer(description: "Maximum number of chunks to create")
          |> Zoi.default(500),
        preview_bytes:
          Zoi.integer(description: "Bytes to include in each chunk preview")
          |> Zoi.default(100)
      })

  alias Jido.AI.RLM.ContextStore
  alias Jido.AI.RLM.WorkspaceStore

  @impl Jido.Action
  @spec run(map(), map()) :: {:ok, map()} | {:error, any()}
  def run(params, context) do
    with {:ok, data} <- ContextStore.fetch(context.context_ref) do
      strategy = params[:strategy] || "lines"
      size = params[:size] || 1000
      overlap = params[:overlap] || 0
      max_chunks = params[:max_chunks] || 500
      preview_bytes = params[:preview_bytes] || 100

      chunks = build_chunks(data, strategy, size, overlap)
      chunks = Enum.take(chunks, max_chunks)

      index =
        Map.new(chunks, fn chunk ->
          {chunk.id, %{byte_start: chunk.byte_start, byte_end: chunk.byte_end, lines: chunk.lines}}
        end)

      WorkspaceStore.update(context.workspace_ref, fn ws ->
        Map.put(ws, :chunks, %{strategy: strategy, size: size, index: index})
      end)

      chunk_descriptors =
        Enum.map(chunks, fn chunk ->
          preview = binary_part(data, chunk.byte_start, min(preview_bytes, chunk.byte_end - chunk.byte_start))
          %{id: chunk.id, lines: chunk.lines, preview: preview}
        end)

      {:ok, %{chunk_count: length(chunks), chunks: chunk_descriptors}}
    end
  end

  defp build_chunks(data, "lines", size, overlap) do
    total_bytes = byte_size(data)
    newline_offsets = :binary.matches(data, "\n")
    line_starts = [0 | Enum.map(newline_offsets, fn {pos, _} -> pos + 1 end)]
    total_lines = length(line_starts)
    line_starts_arr = List.to_tuple(line_starts)
    step = max(size - overlap, 1)

    Stream.iterate(0, &(&1 + step))
    |> Enum.take_while(&(&1 < total_lines))
    |> Enum.with_index()
    |> Enum.map(fn {start_line, idx} ->
      end_line = min(start_line + size - 1, total_lines - 1)
      byte_start = elem(line_starts_arr, start_line)

      byte_end =
        if end_line + 1 < total_lines do
          elem(line_starts_arr, end_line + 1)
        else
          total_bytes
        end

      %{
        id: "c_#{idx}",
        byte_start: byte_start,
        byte_end: byte_end,
        lines: "#{start_line + 1}-#{end_line + 1}"
      }
    end)
  end

  defp build_chunks(data, "bytes", size, overlap) do
    total = byte_size(data)
    step = max(size - overlap, 1)

    Stream.iterate(0, &(&1 + step))
    |> Enum.take_while(&(&1 < total))
    |> Enum.with_index()
    |> Enum.map(fn {byte_start, idx} ->
      byte_end = min(byte_start + size, total)

      %{
        id: "c_#{idx}",
        byte_start: byte_start,
        byte_end: byte_end,
        lines: nil
      }
    end)
  end
end
