defmodule Jido.AI.RLM.ChunkProjection do
  @moduledoc """
  Chunk projection lifecycle for RLM context exploration.

  A chunk projection is a workspace artifact that maps chunk IDs to byte ranges
  over a specific context fingerprint. Projections are immutable snapshots.
  Tools consume projections by ID, and may auto-build one when missing.
  """

  alias Jido.AI.RLM.{ContextStore, WorkspaceStore}

  @default_spec %{
    strategy: "lines",
    size: 1000,
    overlap: 0,
    max_chunks: 500,
    preview_bytes: 100
  }

  @projection_kind :chunks

  @type chunk_meta :: %{
          byte_start: non_neg_integer(),
          byte_end: non_neg_integer(),
          lines: String.t() | nil
        }

  @type projection :: %{
          id: String.t(),
          kind: :chunks,
          context_fingerprint: binary() | nil,
          context_size_bytes: non_neg_integer(),
          chunk_count: non_neg_integer(),
          spec: map(),
          index: %{optional(String.t()) => chunk_meta()},
          chunks: [map()],
          inserted_at: DateTime.t()
        }

  @spec default_spec() :: map()
  def default_spec, do: @default_spec

  @spec create(WorkspaceStore.workspace_ref(), ContextStore.context_ref(), map(), map()) ::
          {:ok, projection(), [map()]} | {:error, term()}
  def create(workspace_ref, context_ref, params \\ %{}, defaults \\ %{}) do
    spec = projection_spec(params, defaults)

    with {:ok, data} <- ContextStore.fetch(context_ref) do
      chunks =
        build_chunks(data, spec.strategy, spec.size, spec.overlap)
        |> Enum.take(spec.max_chunks)

      projection = build_projection(context_ref, chunks, data, spec)
      persist_projection(workspace_ref, projection)
      {:ok, projection, projection.chunks}
    end
  end

  @spec ensure(WorkspaceStore.workspace_ref(), ContextStore.context_ref(), map(), map()) ::
          {:ok, projection()} | {:error, term()}
  def ensure(workspace_ref, context_ref, params \\ %{}, defaults \\ %{}) do
    workspace = WorkspaceStore.get(workspace_ref)
    projection_id = get_param(params, :projection_id, nil) || active_projection_id(workspace)

    with {:ok, projection} <- resolve_projection(workspace, projection_id),
         :ok <- validate_context_fingerprint(projection, context_ref) do
      {:ok, projection}
    else
      _ ->
        case create(workspace_ref, context_ref, params, defaults) do
          {:ok, projection, _chunks} -> {:ok, projection}
          error -> error
        end
    end
  end

  @spec fetch(WorkspaceStore.workspace_ref(), String.t() | nil) ::
          {:ok, projection()} | {:error, :projection_not_found}
  def fetch(workspace_ref, projection_id \\ nil) do
    workspace = WorkspaceStore.get(workspace_ref)
    resolve_projection(workspace, projection_id || active_projection_id(workspace))
  end

  @spec active_projection_id(map()) :: String.t() | nil
  def active_projection_id(workspace) do
    get_in(workspace, [:active_projections, @projection_kind])
  end

  @spec projection_spec(map(), map()) :: map()
  def projection_spec(params, defaults \\ %{}) do
    %{
      strategy: get_param(params, :strategy, get_param(defaults, :strategy, @default_spec.strategy)),
      size: get_param(params, :size, get_param(defaults, :size, @default_spec.size)),
      overlap: get_param(params, :overlap, get_param(defaults, :overlap, @default_spec.overlap)),
      max_chunks: get_param(params, :max_chunks, get_param(defaults, :max_chunks, @default_spec.max_chunks)),
      preview_bytes:
        get_param(
          params,
          :preview_bytes,
          get_param(defaults, :preview_bytes, @default_spec.preview_bytes)
        )
    }
    |> normalize_spec()
  end

  @spec lookup_chunk(projection(), String.t()) :: {:ok, chunk_meta()} | {:error, :chunk_not_found}
  def lookup_chunk(projection, chunk_id) do
    case Map.fetch(projection.index, chunk_id) do
      {:ok, info} -> {:ok, info}
      :error -> {:error, :chunk_not_found}
    end
  end

  @spec sorted_chunks(projection()) :: tuple()
  def sorted_chunks(projection) do
    projection.index
    |> Enum.map(fn {id, %{byte_start: bs, byte_end: be}} -> {bs, be, id} end)
    |> Enum.sort()
    |> List.to_tuple()
  end

  @spec chunk_ids(projection()) :: [String.t()]
  def chunk_ids(projection) do
    projection.chunks
    |> Enum.map(& &1.id)
  end

  defp resolve_projection(_workspace, nil), do: {:error, :projection_not_found}

  defp resolve_projection(workspace, projection_id) do
    case get_in(workspace, [:projections, @projection_kind, projection_id]) do
      nil -> {:error, :projection_not_found}
      projection -> {:ok, projection}
    end
  end

  defp validate_context_fingerprint(projection, context_ref) do
    expected = Map.get(projection, :context_fingerprint)
    current = Map.get(context_ref, :fingerprint)

    if expected == nil or current == nil or expected == current do
      :ok
    else
      {:error, :stale_projection}
    end
  end

  defp persist_projection(workspace_ref, projection) do
    WorkspaceStore.update(workspace_ref, fn ws ->
      projections =
        ws
        |> Map.get(:projections, %{})
        |> Map.update(@projection_kind, %{projection.id => projection}, &Map.put(&1, projection.id, projection))

      active =
        ws
        |> Map.get(:active_projections, %{})
        |> Map.put(@projection_kind, projection.id)

      ws
      |> Map.put(:projections, projections)
      |> Map.put(:active_projections, active)
    end)
  end

  defp build_projection(context_ref, chunks, data, spec) do
    chunk_descriptors =
      Enum.map(chunks, fn chunk ->
        preview_len = min(spec.preview_bytes, chunk.byte_end - chunk.byte_start)
        preview = binary_part(data, chunk.byte_start, preview_len)

        %{
          id: chunk.id,
          lines: chunk.lines,
          byte_start: chunk.byte_start,
          byte_end: chunk.byte_end,
          size_bytes: chunk.byte_end - chunk.byte_start,
          preview: preview
        }
      end)

    index =
      Map.new(chunks, fn chunk ->
        {chunk.id, %{byte_start: chunk.byte_start, byte_end: chunk.byte_end, lines: chunk.lines}}
      end)

    %{
      id: "proj_chunks_#{Jido.Util.generate_id()}",
      kind: @projection_kind,
      context_fingerprint: Map.get(context_ref, :fingerprint),
      context_size_bytes: ContextStore.size(context_ref),
      chunk_count: length(chunks),
      spec: spec,
      index: index,
      chunks: chunk_descriptors,
      inserted_at: DateTime.utc_now()
    }
  end

  defp normalize_spec(spec) do
    %{
      strategy: normalize_strategy(spec.strategy),
      size: normalize_int(spec.size, @default_spec.size, min: 1),
      overlap: normalize_int(spec.overlap, @default_spec.overlap, min: 0),
      max_chunks: normalize_int(spec.max_chunks, @default_spec.max_chunks, min: 1),
      preview_bytes: normalize_int(spec.preview_bytes, @default_spec.preview_bytes, min: 1)
    }
  end

  defp normalize_strategy("bytes"), do: "bytes"
  defp normalize_strategy("lines"), do: "lines"
  defp normalize_strategy(_), do: "lines"

  defp normalize_int(v, fallback, opts) do
    min = Keyword.get(opts, :min, 0)

    cond do
      is_integer(v) -> max(v, min)
      true -> fallback
    end
  end

  defp get_param(map, key, default) when is_map(map) do
    cond do
      Map.has_key?(map, key) ->
        Map.get(map, key)

      Map.has_key?(map, Atom.to_string(key)) ->
        Map.get(map, Atom.to_string(key))

      true ->
        default
    end
  end

  defp get_param(_map, _key, default), do: default

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
