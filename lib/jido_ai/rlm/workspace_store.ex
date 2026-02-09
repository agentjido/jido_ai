defmodule Jido.AI.RLM.WorkspaceStore do
  @moduledoc """
  Per-request exploration state that tools read and write.

  Workspace state is stored via a `Jido.AI.RLM.Workspace` adapter.
  Tools use `update/2` to accumulate exploration progress (chunks indexed,
  hits found, notes, subquery results, etc.) and `summary/2` to produce
  a compact text representation of that progress.

  ## Usage

      {:ok, ref} = WorkspaceStore.init("req-123")
      workspace = WorkspaceStore.get(ref)
      :ok = WorkspaceStore.update(ref, &Map.put(&1, :hits, ["match"]))
      text = WorkspaceStore.summary(ref)
      :ok = WorkspaceStore.delete(ref)
  """

  alias Jido.AI.RLM.Workspace

  @default_max_chars 2000
  @workspace_key :workspace

  @type workspace_ref :: Workspace.ref()

  @spec init(String.t(), map(), keyword()) :: {:ok, workspace_ref()}
  def init(request_id, seed \\ %{}, opts \\ []) do
    case Workspace.init(request_id, opts) do
      {:ok, ref} ->
        :ok = Workspace.put(ref, @workspace_key, seed)
        {:ok, ref}

      error ->
        error
    end
  end

  @spec get(workspace_ref()) :: map()
  def get(ref) do
    case Workspace.fetch(ref, @workspace_key) do
      {:ok, workspace} -> workspace
      :error -> %{}
    end
  end

  @spec update(workspace_ref(), (map() -> map())) :: :ok
  def update(ref, fun) when is_function(fun, 1) do
    Workspace.update(ref, @workspace_key, %{}, fun)
  end

  @spec summary(workspace_ref(), keyword()) :: String.t()
  def summary(ref, opts \\ []) do
    max_chars = Keyword.get(opts, :max_chars, @default_max_chars)
    workspace = get(ref)

    parts =
      [
        chunks_summary(workspace),
        hits_summary(workspace),
        searches_summary(workspace),
        notes_summary(workspace),
        subquery_summary(workspace)
      ]
      |> Enum.reject(&is_nil/1)

    result = Enum.join(parts, " ")

    if byte_size(result) > max_chars do
      binary_part(result, 0, max_chars - 3) <> "..."
    else
      result
    end
  end

  @spec delete(workspace_ref()) :: :ok
  def delete(ref) do
    Workspace.destroy(ref)
  end

  defp chunks_summary(%{chunks: chunks}) when is_list(chunks) do
    count = length(chunks)
    total_size = chunks |> Enum.map(&chunk_size/1) |> Enum.sum()
    "Chunks: #{count} indexed (size #{total_size})."
  end

  defp chunks_summary(%{chunks: %{count: count, type: type, size: size}}) do
    "Chunks: #{count} indexed (#{type}, size #{size})."
  end

  defp chunks_summary(_), do: nil

  defp hits_summary(%{hits: hits}) when is_list(hits) do
    "Hits: #{length(hits)} found."
  end

  defp hits_summary(_), do: nil

  defp searches_summary(%{searches: searches}) when is_list(searches) and length(searches) > 0 do
    count = length(searches)
    latest = hd(searches)
    "Searches: #{count} performed (latest: \"#{latest.query}\")."
  end

  defp searches_summary(_), do: nil

  defp notes_summary(%{notes: notes}) when is_list(notes) do
    count = length(notes)
    grouped = Enum.group_by(notes, &note_type/1)

    type_counts =
      grouped
      |> Enum.map(fn {type, items} -> "#{length(items)} #{type}" end)
      |> Enum.join(", ")

    "Notes: #{count} (#{type_counts})."
  end

  defp notes_summary(_), do: nil

  defp subquery_summary(%{subqueries: subqueries}) when is_list(subqueries) do
    completed = Enum.count(subqueries, &subquery_completed?/1)
    "Subquery results: #{completed} completed."
  end

  defp subquery_summary(_), do: nil

  defp chunk_size(%{size: size}), do: size
  defp chunk_size(chunk) when is_binary(chunk), do: byte_size(chunk)
  defp chunk_size(_), do: 0

  defp note_type(%{type: type}), do: type
  defp note_type(_), do: "note"

  defp subquery_completed?(%{status: :completed}), do: true
  defp subquery_completed?(%{status: "completed"}), do: true
  defp subquery_completed?(_), do: false
end
