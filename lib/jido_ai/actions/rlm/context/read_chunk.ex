defmodule Jido.AI.Actions.RLM.Context.ReadChunk do
  @moduledoc """
  Read the text content of a specific chunk.

  Looks up chunk boundaries from the workspace index and fetches the
  corresponding byte range from the context store.

  ## Parameters

  * `chunk_id` (required) - The chunk identifier (e.g., `"c_0"`)
  * `projection_id` (optional) - Chunk projection ID to read from (defaults to active projection)
  * `max_bytes` (optional) - Maximum bytes to return (default: `50_000`)

  ## Returns

      %{
        chunk_id: "c_0",
        text: "chunk content...",
        byte_start: 0,
        byte_end: 5000,
        truncated: false
      }
  """

  use Jido.Action,
    name: "context_read_chunk",
    description: "Read the text content of a specific chunk",
    category: "rlm",
    tags: ["rlm", "context", "reading"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        chunk_id: Zoi.string(description: "The chunk identifier (e.g., 'c_0')"),
        projection_id:
          Zoi.string(description: "Projection ID; defaults to active chunk projection")
          |> Zoi.optional(),
        max_bytes:
          Zoi.integer(description: "Maximum bytes to return")
          |> Zoi.default(50_000)
      })

  alias Jido.AI.RLM.ChunkProjection
  alias Jido.AI.RLM.ContextStore

  @impl Jido.Action
  @spec run(map(), map()) :: {:ok, map()} | {:error, any()}
  def run(params, context) do
    chunk_id = params[:chunk_id]
    max_bytes = params[:max_bytes] || 50_000
    projection_id = params[:projection_id]
    defaults = Map.get(context, :chunk_defaults, %{})

    with {:ok, projection} <-
           ChunkProjection.ensure(
             context.workspace_ref,
             context.context_ref,
             %{projection_id: projection_id},
             defaults
           ),
         {:ok, chunk_info} <- lookup_chunk(projection, chunk_id) do
      byte_start = chunk_info.byte_start
      byte_end = chunk_info.byte_end
      chunk_size = byte_end - byte_start
      read_size = min(chunk_size, max_bytes)
      truncated = read_size < chunk_size

      with {:ok, text} <- ContextStore.fetch_range(context.context_ref, byte_start, read_size) do
        {:ok,
         %{
           chunk_id: chunk_id,
           projection_id: projection.id,
           text: text,
           byte_start: byte_start,
           byte_end: byte_start + read_size,
           truncated: truncated
         }}
      end
    end
  end

  defp lookup_chunk(projection, chunk_id) do
    case ChunkProjection.lookup_chunk(projection, chunk_id) do
      {:ok, info} -> {:ok, info}
      {:error, :chunk_not_found} -> {:error, "chunk not found: #{chunk_id}"}
    end
  end
end
