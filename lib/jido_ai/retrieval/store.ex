defmodule Jido.AI.Retrieval.Store do
  @moduledoc """
  In-process retrieval memory store backed by ETS.
  """

  @table :jido_ai_retrieval_store
  @heir_name :jido_ai_retrieval_store_heir

  @type memory :: %{
          required(:id) => String.t(),
          required(:text) => String.t(),
          optional(:metadata) => map(),
          optional(:inserted_at_ms) => non_neg_integer(),
          optional(:updated_at_ms) => non_neg_integer()
        }

  @doc """
  Inserts or updates a memory entry in the given namespace.
  """
  @spec upsert(String.t(), memory()) :: memory()
  def upsert(namespace, memory) when is_binary(namespace) and is_map(memory) do
    ensure_table!()

    now = System.system_time(:millisecond)
    id = to_string(Map.get(memory, :id) || Map.get(memory, "id") || "mem_#{Jido.Util.generate_id()}")
    text = to_string(Map.get(memory, :text) || Map.get(memory, "text") || "")
    metadata = Map.get(memory, :metadata) || Map.get(memory, "metadata") || %{}

    existing =
      case :ets.lookup(@table, {namespace, id}) do
        [{{^namespace, ^id}, current}] -> current
        _ -> %{}
      end

    entry =
      existing
      |> Map.merge(%{
        id: id,
        text: text,
        metadata: metadata,
        inserted_at_ms: Map.get(existing, :inserted_at_ms, now),
        updated_at_ms: now
      })

    :ets.insert(@table, {{namespace, id}, entry})
    entry
  end

  @doc """
  Recalls top-k memories for a query using simple token-overlap scoring.
  """
  @spec recall(String.t(), String.t(), keyword()) :: [map()]
  def recall(namespace, query, opts \\ []) when is_binary(namespace) and is_binary(query) do
    ensure_table!()

    top_k = Keyword.get(opts, :top_k, 3)
    min_score = Keyword.get(opts, :min_score, 0.0)

    namespace_entries(namespace)
    |> Enum.map(fn entry ->
      score = score(query, entry.text)
      Map.put(entry, :score, score)
    end)
    |> Enum.filter(&(&1.score >= min_score))
    |> Enum.sort_by(fn entry -> {-entry.score, -(entry.updated_at_ms || 0)} end)
    |> Enum.take(top_k)
  end

  @doc """
  Clears all memories from a namespace and returns the number removed.
  """
  @spec clear(String.t()) :: non_neg_integer()
  def clear(namespace) when is_binary(namespace) do
    ensure_table!()

    keys =
      @table
      |> :ets.tab2list()
      |> Enum.flat_map(fn
        {{^namespace, id}, _entry} -> [{namespace, id}]
        _ -> []
      end)

    Enum.each(keys, &:ets.delete(@table, &1))
    length(keys)
  end

  @doc """
  Returns all memory entries in a namespace.
  """
  @spec namespace_entries(String.t()) :: [memory()]
  def namespace_entries(namespace) when is_binary(namespace) do
    ensure_table!()

    @table
    |> :ets.tab2list()
    |> Enum.flat_map(fn
      {{^namespace, _id}, entry} -> [entry]
      _ -> []
    end)
  end

  @doc """
  Ensures the ETS table exists.
  """
  @spec ensure_table!() :: :ok
  def ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        create_table!()

      _tid ->
        :ok
    end
  end

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

  defp create_table! do
    heir = ensure_heir!()

    :ets.new(@table, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true},
      {:heir, heir, :ok}
    ])

    :ok
  rescue
    ArgumentError ->
      # Another process may have created the table concurrently.
      :ok
  end

  defp ensure_heir! do
    case Process.whereis(@heir_name) do
      nil ->
        pid = spawn(fn -> heir_loop() end)

        try do
          Process.register(pid, @heir_name)
          pid
        rescue
          ArgumentError ->
            Process.exit(pid, :normal)
            Process.whereis(@heir_name) || pid
        end

      pid ->
        pid
    end
  end

  defp heir_loop do
    receive do
      {:"ETS-TRANSFER", _table, _from, _heir_data} ->
        heir_loop()

      _ ->
        heir_loop()
    end
  end
end
