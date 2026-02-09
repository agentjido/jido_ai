defmodule Jido.AI.Actions.RLM.Context.ReadChunk do
  @moduledoc """
  Read the text content of a specific chunk.

  Looks up chunk boundaries from the workspace index and fetches the
  corresponding byte range from the context store.

  ## Parameters

  * `chunk_id` (required) - The chunk identifier (e.g., `"c_0"`)
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
        max_bytes:
          Zoi.integer(description: "Maximum bytes to return")
          |> Zoi.default(50_000)
      })

  alias Jido.AI.RLM.ContextStore
  alias Jido.AI.RLM.WorkspaceStore

  @impl Jido.Action
  @spec run(map(), map()) :: {:ok, map()} | {:error, any()}
  def run(params, context) do
    chunk_id = params[:chunk_id]
    max_bytes = params[:max_bytes] || 50_000

    workspace = WorkspaceStore.get(context.workspace_ref)

    with {:ok, chunk_info} <- lookup_chunk(workspace, chunk_id) do
      byte_start = chunk_info.byte_start
      byte_end = chunk_info.byte_end
      chunk_size = byte_end - byte_start
      read_size = min(chunk_size, max_bytes)
      truncated = read_size < chunk_size

      with {:ok, text} <- ContextStore.fetch_range(context.context_ref, byte_start, read_size) do
        {:ok,
         %{
           chunk_id: chunk_id,
           text: text,
           byte_start: byte_start,
           byte_end: byte_start + read_size,
           truncated: truncated
         }}
      end
    end
  end

  defp lookup_chunk(%{chunks: %{index: index}}, chunk_id) do
    case Map.fetch(index, chunk_id) do
      {:ok, info} -> {:ok, info}
      :error -> {:error, "chunk not found: #{chunk_id}"}
    end
  end

  defp lookup_chunk(_, _chunk_id) do
    {:error, "no chunks indexed — run context_chunk first"}
  end
end
