defmodule Jido.AI.RLM.ContextStore do
  @moduledoc """
  Stores large input context and returns a reference for tools to access it.

  Three storage tiers are used based on configuration:

    * `:inline` — for data below the inline threshold (default 2 MB).
      Data is stored directly in the reference map.
    * `:workspace` — data is stored in a `Jido.AI.RLM.Workspace` ref.
      The workspace owns the ETS table lifecycle, preventing leaks.
    * `:ets` — legacy tier for data at or above the threshold when no
      workspace ref is provided. Creates its own ETS table.

  ## Usage

      {:ok, ref} = ContextStore.put(large_binary, "req-123", workspace_ref: ws_ref)
      {:ok, data} = ContextStore.fetch(ref)
      {:ok, slice} = ContextStore.fetch_range(ref, 0, 100)
      byte_count = ContextStore.size(ref)
      :ok = ContextStore.delete(ref)
  """

  alias Jido.AI.RLM.Workspace

  @default_inline_threshold 2_000_000

  @type inline_ref :: %{backend: :inline, data: binary(), size_bytes: non_neg_integer()}
  @type workspace_ref :: %{
          backend: :workspace,
          workspace_ref: Workspace.ref(),
          key: term(),
          size_bytes: non_neg_integer()
        }
  @type ets_ref :: %{
          backend: :ets,
          table: :ets.tid(),
          key: {String.t(), :context},
          size_bytes: non_neg_integer()
        }
  @type context_ref :: inline_ref() | workspace_ref() | ets_ref()

  @spec put(binary(), String.t(), keyword()) :: {:ok, context_ref()}
  def put(context, request_id, opts \\ []) when is_binary(context) do
    threshold = Keyword.get(opts, :inline_threshold, @default_inline_threshold)
    size_bytes = byte_size(context)

    if size_bytes < threshold do
      {:ok, %{backend: :inline, data: context, size_bytes: size_bytes}}
    else
      case Keyword.get(opts, :workspace_ref) do
        nil ->
          table = Keyword.get(opts, :table) || :ets.new(:context_store, [:set, :public])
          key = {request_id, :context}
          :ets.insert(table, {key, context})
          {:ok, %{backend: :ets, table: table, key: key, size_bytes: size_bytes}}

        ws_ref ->
          key = {:context, request_id}
          :ok = Workspace.put(ws_ref, key, context)
          {:ok, %{backend: :workspace, workspace_ref: ws_ref, key: key, size_bytes: size_bytes}}
      end
    end
  end

  @spec fetch(context_ref()) :: {:ok, binary()} | {:error, :not_found}
  def fetch(%{backend: :inline, data: data}), do: {:ok, data}

  def fetch(%{backend: :ets, table: table, key: key}) do
    case :ets.lookup(table, key) do
      [{^key, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  def fetch(%{backend: :workspace, workspace_ref: ws_ref, key: key}) do
    case Workspace.fetch(ws_ref, key) do
      {:ok, data} -> {:ok, data}
      :error -> {:error, :not_found}
    end
  end

  @spec fetch_range(context_ref(), non_neg_integer(), non_neg_integer()) ::
          {:ok, binary()} | {:error, :not_found}
  def fetch_range(ref, byte_offset, length) do
    case fetch(ref) do
      {:ok, data} -> {:ok, binary_part(data, byte_offset, length)}
      error -> error
    end
  end

  @spec delete(context_ref()) :: :ok
  def delete(%{backend: :inline}), do: :ok

  def delete(%{backend: :ets, table: table, key: key}) do
    :ets.delete(table, key)
    :ok
  end

  def delete(%{backend: :workspace, workspace_ref: ws_ref, key: key}) do
    Workspace.delete_key(ws_ref, key)
  end

  @spec size(context_ref()) :: non_neg_integer()
  def size(%{size_bytes: size_bytes}), do: size_bytes
end
