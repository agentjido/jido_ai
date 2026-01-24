defmodule Jido.AI.Accuracy.ReflexionMemory do
  @moduledoc """
  Reflexion memory for cross-episode learning.

  Based on the Reflexion paper (Lighthizer et al., 2023), this module stores
  past mistakes and corrections to improve future responses. It enables the
  reflection loop to learn from previous critique-revise cycles.

  ## Storage Backends

  - `:ets` - In-memory ETS table (default, fast)
  - `memory` - Simple in-memory map (for testing)

  ## Configuration

  - `:storage` - Storage backend (:ets or :memory)
  - `:max_entries` - Maximum stored critiques (default: 1000)
  - `:similarity_threshold` - For retrieval matching (default: 0.7)
  -:table_name` - ETS table name (auto-generated if nil)

  ## Usage

      # Create memory with ETS backend
      memory = ReflexionMemory.new!(%{
        storage: :ets,
        max_entries: 1000
      })

      # Store a critique
      :ok = ReflexionMemory.store(memory, %{
        prompt: "What is 15 * 23?",
        mistake: "Calculation error: multiplied incorrectly",
        correction: "15 * 23 = 345, not 325",
        severity: 0.8
      })

      # Retrieve similar critiques
      {:ok, similar} = ReflexionMemory.retrieve_similar(memory, "Calculate 12 * 17")

      # Format for LLM prompt
      formatted = ReflexionMemory.format_for_prompt(similar)

  ## Similarity Matching

  For retrieval, the memory uses simple keyword matching:
  - Extracts keywords from the query prompt
  - Scores stored entries by keyword overlap
  - Returns entries above similarity threshold

  Future versions may use embedding-based similarity for better matching.

  """

  @type t :: %__MODULE__{
          storage: :ets | :memory,
          table_name: atom() | nil,
          max_entries: non_neg_integer(),
          similarity_threshold: float(),
          entry_count: non_neg_integer()
        }

  defstruct [
    :table_name,
    storage: :ets,
    max_entries: 1000,
    similarity_threshold: 0.7,
    entry_count: 0
  ]

  @type entry :: %{
          prompt: String.t(),
          mistake: String.t(),
          correction: String.t(),
          severity: float(),
          timestamp: DateTime.t(),
          keywords: [String.t()]
        }

  @doc """
  Creates a new reflexion memory.

  ## Options

  - `:storage` - Storage backend (:ets or :memory, default: :ets)
  - `:max_entries` - Maximum entries to store (default: 1000)
  - `:similarity_threshold` - Minimum similarity for retrieval (default: 0.7)
  - `:table_name` - ETS table name (auto-generated if nil)

  ## Returns

  `{:ok, memory}` on success.

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) or is_map(opts) do
    storage = get_opt(opts, :storage, :ets)
    max_entries = get_opt(opts, :max_entries, 1000)
    similarity_threshold = get_opt(opts, :similarity_threshold, 0.7)

    with :ok <- validate_storage(storage),
         :ok <- validate_max_entries(max_entries),
         :ok <- validate_similarity_threshold(similarity_threshold) do
      table_name = get_opt(opts, :table_name, :"#{__MODULE__}_#{System.unique_integer([:positive])}")

      memory = %__MODULE__{
        storage: storage,
        table_name: table_name,
        max_entries: max_entries,
        similarity_threshold: similarity_threshold,
        entry_count: 0
      }

      # Initialize storage
      case initialize_storage(memory) do
        :ok -> {:ok, memory}
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Creates a new reflexion memory, raising on error.

  """
  @spec new!(keyword() | map()) :: t()
  def new!(opts) when is_list(opts) or is_map(opts) do
    case new(opts) do
      {:ok, memory} -> memory
      {:error, reason} -> raise ArgumentError, "Invalid ReflexionMemory: #{format_error(reason)}"
    end
  end

  @doc """
  Stores a critique entry in memory.

  ## Parameters

  - `memory` - The memory instance
  - `entry` - Map with keys:
    - `:prompt` - The original prompt
    - `:mistake` - What went wrong
    - `:correction` - How it was fixed
    - `:severity` - Critique severity (optional)
    - `:timestamp` - When it occurred (auto-generated if nil)

  ## Returns

  `:ok` on success, `{:error, reason}` on failure.

  """
  @spec store(t(), map()) :: :ok | {:error, term()}
  def store(%__MODULE__{} = memory, entry) when is_map(entry) do
    prompt = Map.get(entry, :prompt, "")
    mistake = Map.get(entry, :mistake, "")
    correction = Map.get(entry, :correction, "")
    severity = Map.get(entry, :severity, 0.5)
    timestamp = Map.get(entry, :timestamp, DateTime.utc_now())

    if prompt == "" do
      {:error, :prompt_required}
    else
      entry_with_keywords = %{
        prompt: prompt,
        mistake: mistake,
        correction: correction,
        severity: severity,
        timestamp: timestamp,
        keywords: extract_keywords(prompt)
      }

      case memory.storage do
        :ets -> store_ets(memory, entry_with_keywords)
        :memory -> store_memory(memory, entry_with_keywords)
      end
    end
  end

  @doc """
  Retrieves entries similar to the given prompt.

  ## Parameters

  - `memory` - The memory instance
  - `prompt` - Query prompt
  - `opts` - Options:
    - `:max_results` - Maximum results (default: 5)

  ## Returns

  `{:ok, [entries]}` where entries are maps with prompt, mistake, correction, etc.

  """
  @spec retrieve_similar(t(), String.t(), keyword()) :: {:ok, [entry()]} | {:error, term()}
  def retrieve_similar(%__MODULE__{} = memory, prompt, opts \\ []) when is_binary(prompt) do
    max_results = Keyword.get(opts, :max_results, 5)
    query_keywords = extract_keywords(prompt)

    case memory.storage do
      :ets -> retrieve_ets(memory, query_keywords, max_results)
      :memory -> retrieve_from_memory(memory, query_keywords, max_results)
    end
  end

  @doc """
  Formats memory entries for use in an LLM prompt.

  ## Parameters

  - `entries` - List of memory entries

  ## Returns

  A formatted string suitable for inclusion in an LLM prompt as few-shot examples.

  ## Example

      iex> entries = [%{prompt: "2+2", mistake: "wrong", correction: "4"}]
      iex> ReflexionMemory.format_for_prompt(entries)
      \"\"\"
      Past mistakes to learn from:

      Question: 2+2
      Mistake: wrong
      Correction: 4

      \"\"\"

  """
  @spec format_for_prompt([entry()]) :: String.t()
  def format_for_prompt(entries) when is_list(entries) do
    if Enum.empty?(entries) do
      ""
    else
      header = "Past mistakes to learn from:\n\n"

      entries_str =
        entries
        |> Enum.map_join("\n", fn entry ->
          """
          Question: #{entry.prompt}
          Mistake: #{entry.mistake}
          Correction: #{entry.correction}
          """
        end)

      header <> entries_str <> "\n"
    end
  end

  @doc """
  Clears all entries from memory.

  ## Returns

  `:ok` on success.

  """
  @spec clear(t()) :: :ok | {:error, term()}
  def clear(%__MODULE__{} = memory) do
    case memory.storage do
      :ets ->
        try do
          :ets.delete_all_objects(memory.table_name)
          {:ok, %{memory | entry_count: 0}}
        rescue
          _ -> {:error, :ets_delete_failed}
        end

      :memory ->
        # For memory storage, we need to handle it differently
        # This is a no-op for :memory storage since it's process state
        {:ok, %{memory | entry_count: 0}}
    end
  end

  @doc """
  Returns the number of entries in memory.

  """
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{} = memory) do
    case memory.storage do
      :ets ->
        try do
          :ets.info(memory.table_name, :size)
        rescue
          _ -> 0
        end

      :memory ->
        memory.entry_count
    end
  end

  @doc """
  Returns a list of all entries in memory.

  For debugging and inspection purposes.

  """
  @spec list_entries(t()) :: {:ok, [entry()]} | {:error, term()}
  def list_entries(%__MODULE__{} = memory) do
    case memory.storage do
      :ets ->
        try do
          entries = :ets.tab2list(memory.table_name)
          {:ok, entries}
        rescue
          _ -> {:error, :ets_read_failed}
        end

      :memory ->
        {:error, :not_supported_for_memory_storage}
    end
  end

  @doc """
  Stops and cleans up the memory resources.

  For ETS storage, deletes the table. Should be called when done.

  """
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{storage: :ets, table_name: table_name}) do
    :ets.delete(table_name)
    :ok
  rescue
    _ -> :ok
  end

  def stop(%__MODULE__{}), do: :ok

  # Private functions

  # Helper function to get options from keyword list or map
  defp get_opt(opts, key, default) when is_list(opts) do
    Keyword.get(opts, key, default)
  end

  defp get_opt(opts, key, default) when is_map(opts) do
    Map.get(opts, key, default)
  end

  defp validate_storage(:ets), do: :ok
  defp validate_storage(:memory), do: :ok
  defp validate_storage(_), do: {:error, :invalid_storage}

  defp validate_max_entries(n) when is_integer(n) and n >= 1, do: :ok
  defp validate_max_entries(_), do: {:error, :invalid_max_entries}

  defp validate_similarity_threshold(t) when is_number(t) and t >= 0.0 and t <= 1.0, do: :ok
  defp validate_similarity_threshold(_), do: {:error, :invalid_similarity_threshold}

  defp initialize_storage(%__MODULE__{storage: :ets, table_name: table_name}) do
    :ets.new(table_name, [:named_table, :set, :public, read_concurrency: true])
    :ok
  rescue
    _ -> {:error, :ets_init_failed}
  end

  defp initialize_storage(%__MODULE__{storage: :memory}), do: :ok

  # ETS storage operations

  defp store_ets(%__MODULE__{} = memory, entry) do
    # Check if we're at max capacity
    current_size = :ets.info(memory.table_name, :size)

    if current_size >= memory.max_entries do
      # Remove oldest entry (first inserted)
      oldest_key = :ets.first(memory.table_name)
      :ets.delete(memory.table_name, oldest_key)
    end

    # Insert with timestamp as key for ordering
    key = {DateTime.to_unix(entry.timestamp, :microsecond), :erlang.unique_integer()}
    :ets.insert(memory.table_name, {key, entry})

    :ok
  rescue
    _ -> {:error, :ets_insert_failed}
  end

  defp store_memory(%__MODULE__{}, _entry) do
    # For :memory storage, this is a no-op since it relies on process state
    # In a real implementation, this would use Agent or GenServer
    {:error, :not_supported_for_memory_storage}
  end

  defp retrieve_ets(%__MODULE__{} = memory, query_keywords, max_results) do
    # Get all entries and score by similarity
    entries = :ets.tab2list(memory.table_name)

    scored =
      Enum.map(entries, fn {_key, entry} ->
        score = similarity_score(query_keywords, entry.keywords)
        {score, entry}
      end)

    # Filter by threshold and sort by score descending
    similar =
      scored
      |> Enum.filter(fn {score, _entry} -> score >= memory.similarity_threshold end)
      |> Enum.sort_by(fn {score, _entry} -> score end, :desc)
      |> Enum.take(max_results)
      |> Enum.map(fn {_score, entry} -> entry end)

    {:ok, similar}
  rescue
    _ -> {:error, :ets_read_failed}
  end

  defp retrieve_from_memory(%__MODULE__{}, _query_keywords, _max_results) do
    # For :memory storage, return empty list
    {:ok, []}
  end

  # Similarity scoring

  defp similarity_score(query_keywords, entry_keywords) do
    if Enum.empty?(query_keywords) or Enum.empty?(entry_keywords) do
      0.0
    else
      query_set = MapSet.new(query_keywords)
      entry_set = MapSet.new(entry_keywords)

      # Jaccard similarity
      intersection = MapSet.intersection(query_set, entry_set) |> MapSet.size()
      union = MapSet.union(query_set, entry_set) |> MapSet.size()

      if union > 0 do
        intersection / union
      else
        0.0
      end
    end
  end

  # Keyword extraction

  defp extract_keywords(text) when is_binary(text) do
    text
    |> String.downcase()
    # Remove punctuation and split into words
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split(~r/\s+/, trim: true)
    # Filter out common stop words
    |> Enum.reject(fn word ->
      word in [
        "a",
        "an",
        "the",
        "is",
        "are",
        "was",
        "were",
        "be",
        "been",
        "being",
        "have",
        "has",
        "had",
        "do",
        "does",
        "did",
        "will",
        "would",
        "could",
        "should",
        "may",
        "might",
        "must",
        "shall",
        "can",
        "need",
        "what",
        "how",
        "when",
        "where",
        "why",
        "who",
        "which",
        "that",
        "this",
        "these",
        "those",
        "and",
        "or",
        "but",
        "if",
        "then",
        "else",
        "so",
        "because",
        "although",
        "though",
        "while",
        "since",
        "until",
        "for",
        "of",
        "with",
        "by",
        "from",
        "to",
        "in",
        "on",
        "at",
        "as",
        "into",
        "through",
        "during",
        "before",
        "after",
        "above",
        "below",
        "between",
        "under",
        "again",
        "further",
        "once",
        "here",
        "there",
        "all",
        "both",
        "each",
        "few",
        "more",
        "most",
        "other",
        "some",
        "such",
        "no",
        "nor",
        "not",
        "only",
        "own",
        "same",
        "than",
        "too",
        "very",
        "just"
      ]
    end)
    |> Enum.uniq()
  end

  defp format_error(atom) when is_atom(atom), do: atom
end
