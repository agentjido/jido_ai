defmodule Jido.AI.Actions.RLM.Context.Search do
  @moduledoc """
  Search the context for a substring or regex pattern.

  Finds matches within the context and returns surrounding text snippets.
  When chunks are indexed in the workspace, maps each hit to the
  corresponding chunk ID.

  ## Parameters

  * `query` (required) - The search string or regex pattern
  * `mode` (optional) - Search mode: `"substring"` or `"regex"` (default: `"substring"`)
  * `limit` (optional) - Maximum number of matches to return (default: `20`)
  * `window_bytes` (optional) - Bytes of surrounding context per match (default: `200`)

  ## Returns

      %{
        total_matches: 3,
        hits: [
          %{offset: 47231, chunk_id: "c_47", snippet: "...surrounding text..."}
        ]
      }
  """

  use Jido.Action,
    name: "context_search",
    description: "Search the context for a substring or regex pattern",
    category: "rlm",
    tags: ["rlm", "context", "search"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        query: Zoi.string(description: "The search string or regex pattern"),
        mode:
          Zoi.enum(["substring", "regex"], description: "Search mode")
          |> Zoi.default("substring"),
        limit:
          Zoi.integer(description: "Maximum number of matches to return")
          |> Zoi.default(20),
        window_bytes:
          Zoi.integer(description: "Bytes of surrounding context per match")
          |> Zoi.default(200)
      })

  alias Jido.AI.RLM.ContextStore
  alias Jido.AI.RLM.WorkspaceStore

  @impl Jido.Action
  @spec run(map(), map()) :: {:ok, map()} | {:error, any()}
  def run(params, context) do
    query = params[:query]
    mode = params[:mode] || "substring"
    limit = params[:limit] || 20
    window_bytes = params[:window_bytes] || 200

    with {:ok, data} <- ContextStore.fetch(context.context_ref),
         {:ok, offsets} <- find_matches(data, query, mode) do
      workspace = WorkspaceStore.get(context.workspace_ref)
      chunk_index = get_in(workspace, [:chunks, :index])
      total_size = byte_size(data)

      hits =
        offsets
        |> Enum.take(limit)
        |> Enum.map(fn offset ->
          snippet = extract_snippet(data, offset, window_bytes, total_size)
          chunk_id = resolve_chunk_id(offset, chunk_index)
          %{offset: offset, chunk_id: chunk_id, snippet: snippet}
        end)

      WorkspaceStore.update(context.workspace_ref, fn ws ->
        Map.put(ws, :hits, hits)
      end)

      {:ok, %{total_matches: length(offsets), hits: hits}}
    end
  end

  defp find_matches(data, query, "substring") do
    offsets = find_substring_offsets(data, query, 0, [])
    {:ok, offsets}
  end

  defp find_matches(data, pattern, "regex") do
    case Regex.compile(pattern) do
      {:ok, regex} ->
        offsets =
          Regex.scan(regex, data, return: :index)
          |> Enum.map(fn [{offset, _length} | _] -> offset end)

        {:ok, offsets}

      {:error, reason} ->
        {:error, "invalid regex: #{inspect(reason)}"}
    end
  end

  defp find_substring_offsets(data, query, start, acc) do
    case :binary.match(data, query, scope: {start, byte_size(data) - start}) do
      {offset, length} ->
        find_substring_offsets(data, query, offset + length, [offset | acc])

      :nomatch ->
        Enum.reverse(acc)
    end
  end

  defp extract_snippet(data, offset, window_bytes, total_size) do
    half_window = div(window_bytes, 2)
    snippet_start = max(0, offset - half_window)
    snippet_end = min(total_size, offset + half_window)
    binary_part(data, snippet_start, snippet_end - snippet_start)
  end

  defp resolve_chunk_id(_offset, nil), do: nil

  defp resolve_chunk_id(offset, chunk_index) do
    Enum.find_value(chunk_index, nil, fn {id, %{byte_start: bs, byte_end: be}} ->
      if offset >= bs and offset < be, do: id
    end)
  end
end
