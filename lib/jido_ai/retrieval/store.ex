defmodule Jido.AI.Retrieval.Store do
  @moduledoc """
  Supervised in-process retrieval memory. Add `{Jido.AI.Retrieval.Store, []}` to an application
  supervisor for the default shared store. No call starts an implicit process.
  Named or unnamed stores can be supplied explicitly. Data lives until that
  store process stops; an Agent checkpoint does not contain this external store.
  """
  use GenServer

  @type memory :: %{
          required(:id) => String.t(),
          required(:text) => String.t(),
          optional(:metadata) => map(),
          optional(:inserted_at_ms) => integer(),
          optional(:updated_at_ms) => integer()
        }

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, if(is_nil(name), do: [], else: [name: name]))
  end

  @doc "Inserts or updates a memory; the store owns the write."
  def upsert(namespace, memory, store \\ __MODULE__)
      when is_binary(namespace) and is_map(memory) do
    memory = normalize_keys(memory)

    entry = %{
      id: to_string(memory[:id] || "mem_#{Jido.Signal.ID.generate!()}"),
      text: to_string(memory[:text] || ""),
      metadata: memory[:metadata] || %{}
    }

    GenServer.call(store, {:upsert, namespace, entry})
  end

  @doc "Recalls top-k entries by token overlap; `store` selects an explicit owner."
  def recall(namespace, query, opts \\ []) when is_binary(namespace) and is_binary(query) do
    namespace_entries(namespace, Keyword.get(opts, :store, __MODULE__))
    |> Enum.map(&Map.put(&1, :score, score(query, &1.text)))
    |> Enum.filter(&(&1.score >= Keyword.get(opts, :min_score, 0.0)))
    |> Enum.sort_by(&{-&1.score, -(&1.updated_at_ms || 0), &1.id})
    |> Enum.take(Keyword.get(opts, :top_k, 3))
  end

  @doc "Clears a namespace atomically and returns its entry count."
  def clear(namespace, store \\ __MODULE__) when is_binary(namespace),
    do: GenServer.call(store, {:clear, namespace})

  @doc "Returns a snapshot of entries in a namespace."
  def namespace_entries(namespace, store \\ __MODULE__) when is_binary(namespace),
    do: GenServer.call(store, {:entries, namespace})

  @doc "Checks that the supervised store is ready; it does not start a store."
  def ensure_table!(store \\ __MODULE__), do: GenServer.call(store, :ready)

  @impl GenServer
  def init(:ok), do: {:ok, :ets.new(__MODULE__, [:set, :private])}

  @impl GenServer
  def handle_call(:ready, _from, table), do: {:reply, :ok, table}

  def handle_call({:entries, namespace}, _from, table),
    do: {:reply, entries(table, namespace), table}

  def handle_call({:clear, namespace}, _from, table) do
    entries = entries(table, namespace)
    Enum.each(entries, &:ets.delete(table, {namespace, &1.id}))
    {:reply, length(entries), table}
  end

  def handle_call({:upsert, namespace, memory}, _from, table) do
    now = System.system_time(:millisecond)
    id = memory.id

    existing =
      case :ets.lookup(table, {namespace, id}) do
        [{{^namespace, ^id}, entry}] -> entry
        _ -> %{}
      end

    entry =
      Map.merge(existing, %{
        id: id,
        text: memory.text,
        metadata: memory.metadata,
        inserted_at_ms: Map.get(existing, :inserted_at_ms, now),
        updated_at_ms: now
      })

    :ets.insert(table, {{namespace, id}, entry})
    {:reply, entry, table}
  end

  defp entries(table, namespace),
    do: :ets.match_object(table, {{namespace, :_}, :_}) |> Enum.map(&elem(&1, 1))

  defp score(query, text) when is_binary(query) and is_binary(text) do
    q_terms = token_set(query)
    t_terms = token_set(text)

    if MapSet.size(q_terms) == 0 or MapSet.size(t_terms) == 0 do
      0.0
    else
      intersection = MapSet.intersection(q_terms, t_terms) |> MapSet.size()
      union = MapSet.union(q_terms, t_terms) |> MapSet.size()
      if union == 0, do: 0.0, else: intersection / union
    end
  end

  defp token_set(input) do
    input
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/u, " ")
    |> String.split(~r/\s+/, trim: true)
    |> MapSet.new()
  end

  defp normalize_keys(memory) do
    Enum.reduce([:id, :text, :metadata], memory, fn key, acc ->
      if Map.has_key?(acc, key),
        do: acc,
        else: Map.put(acc, key, Map.get(memory, Atom.to_string(key)))
    end)
  end
end
