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
          |> Zoi.default(200),
        case_sensitive:
          Zoi.boolean(description: "Whether search is case-sensitive")
          |> Zoi.default(true)
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
    case_sensitive = params[:case_sensitive] != false

    with {:ok, data} <- ContextStore.fetch(context.context_ref),
         {:ok, offsets} <- find_matches(data, query, mode, limit, case_sensitive) do
      workspace = WorkspaceStore.get(context.workspace_ref)
      chunk_index = get_in(workspace, [:chunks, :index])
      sorted_chunks = build_sorted_chunks(chunk_index)
      total_size = byte_size(data)

      hits =
        offsets
        |> Enum.map(fn offset ->
          snippet = extract_snippet(data, offset, window_bytes, total_size)
          chunk_id = resolve_chunk_id(offset, sorted_chunks)
          %{offset: offset, chunk_id: chunk_id, snippet: snippet}
        end)

      WorkspaceStore.update(context.workspace_ref, fn ws ->
        search_entry = %{query: query, mode: mode, hit_count: length(hits), at: DateTime.utc_now()}

        ws
        |> Map.put(:hits, hits)
        |> Map.update(:searches, [search_entry], &[search_entry | &1])
      end)

      {:ok, %{total_matches: length(offsets), hits: hits}}
    end
  end

  defp find_matches(data, query, "substring", limit, true) do
    offsets = find_substring_offsets(data, query, 0, [], limit)
    {:ok, offsets}
  end

  defp find_matches(data, query, "substring", limit, false) do
    case Regex.compile(Regex.escape(query), "i") do
      {:ok, regex} ->
        offsets = find_regex_offsets(regex, data, 0, [], limit)
        {:ok, offsets}

      {:error, reason} ->
        {:error, "invalid query for case-insensitive search: #{inspect(reason)}"}
    end
  end

  defp find_matches(data, pattern, "regex", limit, true) do
    case Regex.compile(pattern) do
      {:ok, regex} ->
        offsets = find_regex_offsets(regex, data, 0, [], limit)
        {:ok, offsets}

      {:error, reason} ->
        {:error, "invalid regex: #{inspect(reason)}"}
    end
  end

  defp find_matches(data, pattern, "regex", limit, false) do
    case Regex.compile(pattern, "i") do
      {:ok, regex} ->
        offsets = find_regex_offsets(regex, data, 0, [], limit)
        {:ok, offsets}

      {:error, reason} ->
        {:error, "invalid regex: #{inspect(reason)}"}
    end
  end

  defp find_substring_offsets(_data, _query, _start, acc, limit) when length(acc) >= limit do
    Enum.reverse(acc)
  end

  defp find_substring_offsets(data, query, start, acc, limit) do
    case :binary.match(data, query, scope: {start, byte_size(data) - start}) do
      {offset, length} ->
        find_substring_offsets(data, query, offset + length, [offset | acc], limit)

      :nomatch ->
        Enum.reverse(acc)
    end
  end

  defp find_regex_offsets(_regex, _data, _start, acc, limit) when length(acc) >= limit do
    Enum.reverse(acc)
  end

  defp find_regex_offsets(regex, data, start, acc, limit) do
    case Regex.run(regex, data, return: :index, offset: start) do
      [{offset, match_length} | _] ->
        find_regex_offsets(regex, data, offset + max(match_length, 1), [offset | acc], limit)

      nil ->
        Enum.reverse(acc)
    end
  end

  defp extract_snippet(data, offset, window_bytes, total_size) do
    half_window = div(window_bytes, 2)
    snippet_start = max(0, offset - half_window)
    snippet_end = min(total_size, offset + half_window)
    binary_part(data, snippet_start, snippet_end - snippet_start)
  end

  defp build_sorted_chunks(nil), do: nil

  defp build_sorted_chunks(chunk_index) do
    chunk_index
    |> Enum.map(fn {id, %{byte_start: bs, byte_end: be}} -> {bs, be, id} end)
    |> Enum.sort()
    |> List.to_tuple()
  end

  defp resolve_chunk_id(_offset, nil), do: nil

  defp resolve_chunk_id(offset, sorted_chunks) do
    binary_search_chunk(sorted_chunks, offset, 0, tuple_size(sorted_chunks) - 1)
  end

  defp binary_search_chunk(_sorted, _offset, lo, hi) when lo > hi, do: nil

  defp binary_search_chunk(sorted, offset, lo, hi) do
    mid = div(lo + hi, 2)
    {bs, be, id} = elem(sorted, mid)

    cond do
      offset >= bs and offset < be -> id
      offset < bs -> binary_search_chunk(sorted, offset, lo, mid - 1)
      true -> binary_search_chunk(sorted, offset, mid + 1, hi)
    end
  end
end
