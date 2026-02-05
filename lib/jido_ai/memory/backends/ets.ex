defmodule Jido.AI.Memory.Backends.ETS do
  @moduledoc """
  ETS-based memory backend.

  Stores memory entries in a named ETS table with `{agent_id, key}` composite keys.
  The table is created on first use as a public named table.

  This backend is suitable for development, testing, and single-node deployments.
  For persistence across restarts or multi-node setups, implement a custom backend.

  ## Configuration

      config :jido_ai, Jido.AI.Memory,
        backend: Jido.AI.Memory.Backends.ETS,
        backend_opts: [table: :my_custom_table]
  """

  @behaviour Jido.AI.Memory

  alias Jido.AI.Memory.Entry

  @default_table :jido_ai_memory

  @impl true
  def store(agent_id, key, value, opts) do
    tab = ensure_table!(opts)
    now = DateTime.utc_now()
    tags = Keyword.get(opts, :tags, [])
    metadata = Keyword.get(opts, :metadata, %{})

    entry =
      case :ets.lookup(tab, {agent_id, key}) do
        [{{^agent_id, ^key}, %Entry{} = existing}] ->
          %{existing | value: value, tags: tags, metadata: metadata, updated_at: now}

        [] ->
          Entry.new(%{
            agent_id: agent_id,
            key: key,
            value: value,
            tags: tags,
            metadata: metadata
          })
      end

    :ets.insert(tab, {{agent_id, key}, entry})
    {:ok, entry}
  end

  @impl true
  def recall(agent_id, %{key: key}, opts) when is_binary(key) do
    tab = ensure_table!(opts)

    case :ets.lookup(tab, {agent_id, key}) do
      [{{^agent_id, ^key}, entry}] -> {:ok, entry}
      [] -> {:ok, nil}
    end
  end

  def recall(agent_id, %{tags: tags}, opts) when is_list(tags) do
    tab = ensure_table!(opts)

    entries =
      :ets.tab2list(tab)
      |> Enum.flat_map(fn
        {{^agent_id, _key}, %Entry{} = entry} -> [entry]
        _ -> []
      end)
      |> Enum.filter(&tags_match?(&1, tags))

    {:ok, entries}
  end

  def recall(_agent_id, _query, _opts), do: {:error, :invalid_query}

  @impl true
  def forget(agent_id, %{key: key}, opts) when is_binary(key) do
    tab = ensure_table!(opts)

    count =
      case :ets.lookup(tab, {agent_id, key}) do
        [_] ->
          :ets.delete(tab, {agent_id, key})
          1

        [] ->
          0
      end

    {:ok, count}
  end

  def forget(agent_id, %{tags: tags}, opts) when is_list(tags) do
    tab = ensure_table!(opts)

    keys_to_delete =
      :ets.tab2list(tab)
      |> Enum.flat_map(fn
        {{^agent_id, key}, %Entry{} = entry} ->
          if tags_match?(entry, tags), do: [{agent_id, key}], else: []

        _ ->
          []
      end)

    Enum.each(keys_to_delete, &:ets.delete(tab, &1))
    {:ok, length(keys_to_delete)}
  end

  def forget(_agent_id, _query, _opts), do: {:error, :invalid_query}

  defp tags_match?(%Entry{tags: entry_tags}, required_tags) do
    Enum.all?(required_tags, &(&1 in entry_tags))
  end

  defp table_name(opts) do
    backend_opts =
      Application.get_env(:jido_ai, Jido.AI.Memory, [])
      |> Keyword.get(:backend_opts, [])

    Keyword.get(opts, :table) ||
      Keyword.get(backend_opts, :table, @default_table)
  end

  defp ensure_table!(opts) do
    tab = table_name(opts)

    case :ets.whereis(tab) do
      :undefined ->
        create_table(tab)

      _tid ->
        :ok
    end

    tab
  end

  defp create_table(tab) do
    parent = self()

    spawn(fn ->
      try do
        :ets.new(tab, [:named_table, :set, :public, read_concurrency: true])
      rescue
        ArgumentError -> :ok
      end

      send(parent, {:table_ready, tab})

      receive do
        :stop -> :ok
      end
    end)

    receive do
      {:table_ready, ^tab} -> :ok
    after
      5_000 -> raise "Timeout waiting for ETS table #{tab}"
    end
  end
end
