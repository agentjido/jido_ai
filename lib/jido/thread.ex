defmodule Jido.Thread do
  @moduledoc """
  A portable append-only interaction log.

  A Thread is an immutable value. It has no process, Plugin, storage adapter,
  Agent behavior, or automatic event capture. Applications can store it in
  declared Agent state and can project its entries for their own use.
  """

  alias __MODULE__.Entry

  @version 1
  @schema Zoi.struct(
            __MODULE__,
            %{
              version: Zoi.integer(description: "Portable format version") |> Zoi.default(@version),
              id: Zoi.string(description: "Unique thread identifier") |> Zoi.min(1),
              rev: Zoi.integer(description: "Monotonic append revision") |> Zoi.min(0) |> Zoi.default(0),
              entries: Zoi.list(Entry.schema(), description: "Ordered thread entries") |> Zoi.default([]),
              created_at: Zoi.integer(description: "Creation timestamp in milliseconds"),
              updated_at: Zoi.integer(description: "Last update timestamp in milliseconds"),
              metadata: Zoi.map(description: "Portable metadata") |> Zoi.default(%{}),
              stats: Zoi.map(description: "Cached aggregates") |> Zoi.default(%{entry_count: 0})
            },
            coerce: true,
            unrecognized_keys: :error
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Thread schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates an empty thread."
  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    now = Keyword.get(opts, :now, System.system_time(:millisecond))

    %__MODULE__{
      version: @version,
      id: Keyword.get(opts, :id, "thread_#{Jido.Util.generate_id()}"),
      rev: 0,
      entries: [],
      created_at: now,
      updated_at: now,
      metadata: Keyword.get(opts, :metadata, %{}),
      stats: %{entry_count: 0}
    }
    |> validate!()
  end

  @doc "Appends one or more entries and returns the complete next value."
  @spec append(t(), Entry.t() | map() | [Entry.t() | map()] | nil) :: t()
  def append(%__MODULE__{} = thread, entries) when entries in [nil, []], do: thread

  def append(%__MODULE__{} = thread, entries) do
    now = max(System.system_time(:millisecond), thread.updated_at)
    base_seq = length(thread.entries)

    appended =
      entries
      |> List.wrap()
      |> Enum.with_index(base_seq)
      |> Enum.map(fn {entry, seq} -> Entry.normalize(entry, seq, now) end)

    count = length(appended)

    %{
      thread
      | entries: thread.entries ++ appended,
        rev: thread.rev + count,
        updated_at: now,
        stats: %{entry_count: thread.stats.entry_count + count}
    }
    |> validate!()
  end

  @doc "Returns the entry count."
  @spec entry_count(t()) :: non_neg_integer()
  def entry_count(%__MODULE__{stats: %{entry_count: count}}), do: count

  @doc "Returns the last entry or nil."
  @spec last(t()) :: Entry.t() | nil
  def last(%__MODULE__{entries: []}), do: nil
  def last(%__MODULE__{entries: entries}), do: List.last(entries)

  @doc "Returns the entry at one sequence number or nil."
  @spec get_entry(t(), non_neg_integer()) :: Entry.t() | nil
  def get_entry(%__MODULE__{entries: entries}, seq), do: Enum.find(entries, &(&1.seq == seq))

  @doc "Returns all entries in chronological order."
  @spec to_list(t()) :: [Entry.t()]
  def to_list(%__MODULE__{entries: entries}), do: entries

  @doc "Returns entries that have the selected kind or kinds."
  @spec filter_by_kind(t() | nil, Entry.kind() | [Entry.kind()]) :: [Entry.t()]
  def filter_by_kind(nil, _kind), do: []

  def filter_by_kind(%__MODULE__{entries: entries}, kinds) when is_list(kinds),
    do: Enum.filter(entries, &(&1.kind in kinds))

  def filter_by_kind(%__MODULE__{entries: entries}, kind)
      when is_atom(kind) or is_binary(kind),
      do: Enum.filter(entries, &(&1.kind == kind))

  @doc "Returns entries in an inclusive sequence range."
  @spec slice(t(), non_neg_integer(), non_neg_integer()) :: [Entry.t()]
  def slice(%__MODULE__{entries: entries}, from_seq, to_seq)
      when is_integer(from_seq) and from_seq >= 0 and is_integer(to_seq) and to_seq >= from_seq,
      do: Enum.filter(entries, &(&1.seq >= from_seq and &1.seq <= to_seq))

  @doc "Returns a portable versioned Thread map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = thread) do
    validate!(thread)

    %{
      "type" => "jido.thread",
      "version" => @version,
      "id" => thread.id,
      "rev" => thread.rev,
      "entries" => Enum.map(thread.entries, &Entry.encode/1),
      "created_at" => thread.created_at,
      "updated_at" => thread.updated_at,
      "metadata" => thread.metadata
    }
  end

  @doc "Decodes a Thread struct or a versioned Thread map."
  @spec decode(t() | map()) :: {:ok, t()} | {:error, :invalid_thread | :unsupported_version}
  def decode(%__MODULE__{} = thread) do
    if Map.has_key?(thread, :version), do: validate(thread), else: decode(Map.from_struct(thread))
  end

  def decode(map) when is_map(map) do
    with :ok <- document_version(map),
         true <- known_keys?(map),
         {:ok, entries} <- decode_entries(field(map, :entries) || []),
         thread = %__MODULE__{
           version: @version,
           id: field(map, :id),
           rev: field(map, :rev) || length(entries),
           entries: entries,
           created_at: field(map, :created_at),
           updated_at: field(map, :updated_at),
           metadata: field(map, :metadata) || %{},
           stats: %{entry_count: length(entries)}
         },
         {:ok, thread} <- validate(thread) do
      {:ok, thread}
    else
      {:error, :unsupported_version} = error -> error
      _ -> {:error, :invalid_thread}
    end
  end

  def decode(_), do: {:error, :invalid_thread}

  @doc false
  @spec validate(t()) :: {:ok, t()} | {:error, :invalid_thread}
  def validate(%__MODULE__{} = thread) do
    valid_entries? =
      is_list(thread.entries) and
        Enum.all?(Enum.with_index(thread.entries), fn {entry, index} ->
          match?({:ok, _}, Entry.validate(entry)) and entry.seq == index
        end)

    with {:ok, _} <- Zoi.parse(@schema, thread),
         true <- thread.version == @version,
         true <- thread.rev == length(thread.entries),
         true <- thread.stats == %{entry_count: length(thread.entries)},
         true <- thread.updated_at >= thread.created_at,
         true <- valid_entries?,
         :ok <- Jido.Action.validate_static_data(thread.metadata) do
      {:ok, thread}
    else
      _ -> {:error, :invalid_thread}
    end
  end

  def validate(_), do: {:error, :invalid_thread}

  defp validate!(thread) do
    case validate(thread) do
      {:ok, thread} -> thread
      {:error, :invalid_thread} -> raise ArgumentError, "invalid thread"
    end
  end

  defp decode_entries(entries) when is_list(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, decoded} ->
      case Entry.decode(entry) do
        {:ok, entry} -> {:cont, {:ok, [entry | decoded]}}
        {:error, _} -> {:halt, {:error, :invalid_thread}}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      error -> error
    end
  end

  defp decode_entries(_), do: {:error, :invalid_thread}

  defp document_version(map) do
    case {field(map, :type), field(map, :version)} do
      {"jido.thread", @version} -> :ok
      _ -> {:error, :unsupported_version}
    end
  end

  defp known_keys?(map) do
    keys = ~w(type version id rev entries created_at updated_at metadata stats __struct__)
    allowed = keys ++ Enum.map(keys, &String.to_atom/1)
    Map.keys(map) -- allowed == []
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
