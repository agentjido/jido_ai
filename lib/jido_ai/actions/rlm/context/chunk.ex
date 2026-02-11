defmodule Jido.AI.Actions.RLM.Context.Chunk do
  @moduledoc """
  Build a chunk projection in workspace for context exploration.

  Supports line-based and byte-based strategies with configurable overlap.
  Stores projections under `workspace[:projections][:chunks]` and marks the
  latest projection as active under `workspace[:active_projections][:chunks]`.

  ## Parameters

  * `strategy` - Chunking strategy: `"lines"` or `"bytes"` (default: `"lines"`)
  * `size` - Lines per chunk or bytes per chunk (default: `1000`)
  * `overlap` - Overlap in lines or bytes between chunks (default: `0`)
  * `max_chunks` - Maximum number of chunks to create (default: `500`)
  * `preview_bytes` - Bytes to include in each chunk preview (default: `100`)

  ## Returns

      %{
        projection_id: "proj_chunks_...",
        chunk_count: 5,
        chunks: [%{id: "c_0", lines: "1-1000", preview: "first 100 bytes..."}],
        spec: %{strategy: "lines", size: 1000, overlap: 0, max_chunks: 500, preview_bytes: 100}
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
        projection_id: Zoi.string() |> Zoi.optional(),
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

  alias Jido.AI.RLM.ChunkProjection

  @impl Jido.Action
  @spec run(map(), map()) :: {:ok, map()} | {:error, any()}
  def run(params, context) do
    defaults = Map.get(context, :chunk_defaults, %{})

    with {:ok, projection, chunks} <-
           ChunkProjection.create(context.workspace_ref, context.context_ref, params, defaults) do
      {:ok,
       %{
         projection_id: projection.id,
         chunk_count: projection.chunk_count,
         chunks: chunks,
         spec: projection.spec
       }}
    end
  end
end
