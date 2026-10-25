defmodule Jido.Thread do
  @moduledoc """
  An immutable, portable, ordered collection of committed Signals.

  A Thread is a value. It does not own a process, a model request, or storage.
  Its revision is the number of Signals that it contains.
  """

  alias Jido.{PortableTerm, Signal}

  @enforce_keys [:id]
  defstruct id: nil, rev: 0, signals: [], metadata: %{}

  @type t :: %__MODULE__{
          id: String.t(),
          rev: non_neg_integer(),
          signals: [Signal.t()],
          metadata: map()
        }

  @doc "Creates an empty Thread."
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ [])

  def new(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs), do: new(Map.new(attrs)), else: {:error, :invalid_thread_options}
  end

  def new(attrs) when is_map(attrs) and not is_struct(attrs) do
    with :ok <- known_keys(attrs, [:id, :metadata]),
         id = Map.get_lazy(attrs, :id, &Signal.ID.generate!/0),
         metadata = Map.get(attrs, :metadata, %{}),
         :ok <- validate_id(id),
         :ok <- validate_metadata(metadata) do
      {:ok, %__MODULE__{id: id, metadata: metadata}}
    end
  end

  def new(_attrs), do: {:error, :invalid_thread_options}

  @doc "Creates an empty Thread or raises."
  @spec new!(keyword() | map()) :: t() | no_return()
  def new!(attrs \\ []) do
    case new(attrs) do
      {:ok, thread} -> thread
      {:error, reason} -> raise ArgumentError, "invalid Thread: #{inspect(reason)}"
    end
  end

  @doc "Appends one Signal and returns a new Thread."
  @spec append(t(), Signal.t()) :: {:ok, t()} | {:error, term()}
  def append(%__MODULE__{} = thread, %Signal{} = signal), do: append_many(thread, [signal])
  def append(%__MODULE__{}, _signal), do: {:error, {:invalid_signal, 0}}
  def append(_thread, _signal), do: {:error, :invalid_thread}

  @doc "Appends a Signal batch atomically and returns a new Thread."
  @spec append_many(t(), [Signal.t()]) :: {:ok, t()} | {:error, term()}
  def append_many(%__MODULE__{} = thread, signals) when is_list(signals) do
    with :ok <- validate(thread),
         :ok <- validate_signals(signals) do
      {:ok,
       %{
         thread
         | rev: thread.rev + length(signals),
           signals: thread.signals ++ signals
       }}
    end
  end

  def append_many(%__MODULE__{}, _signals), do: {:error, :invalid_signals}
  def append_many(_thread, _signals), do: {:error, :invalid_thread}

  @doc "Validates the complete Thread value."
  @spec validate(term()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = thread) do
    with :ok <- validate_id(thread.id),
         :ok <- validate_revision(thread.rev, thread.signals),
         :ok <- validate_metadata(thread.metadata),
         :ok <- validate_signals(thread.signals) do
      validate_portable(thread, [:thread])
    end
  end

  def validate(_thread), do: {:error, :invalid_thread}

  @doc false
  def validate_schema(value, _opts) do
    case validate(value) do
      :ok -> :ok
      {:error, reason} -> {:error, "must be a valid Thread: #{inspect(reason)}"}
    end
  end

  @doc "Returns a schema that accepts valid Thread values."
  @spec schema() :: Zoi.schema()
  def schema, do: Zoi.any() |> Zoi.refine({__MODULE__, :validate_schema, []})

  defp known_keys(attrs, allowed) do
    case Map.keys(attrs) -- allowed do
      [] -> :ok
      keys -> {:error, {:unknown_thread_options, keys}}
    end
  end

  defp validate_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
  defp validate_id(_id), do: {:error, :invalid_thread_id}

  defp validate_revision(rev, signals)
       when is_integer(rev) and rev >= 0 and is_list(signals) and rev == length(signals),
       do: :ok

  defp validate_revision(_rev, _signals), do: {:error, :invalid_thread_revision}

  defp validate_metadata(metadata) when is_map(metadata) and not is_struct(metadata),
    do: validate_portable(metadata, [:thread, :metadata])

  defp validate_metadata(_metadata), do: {:error, :invalid_thread_metadata}

  defp validate_signals(signals) do
    signals
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn
      {%Signal{} = signal, index}, :ok ->
        case validate_signal(signal, index) do
          :ok -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end

      {_signal, index}, :ok ->
        {:halt, {:error, {:invalid_signal, index}}}
    end)
  end

  defp validate_signal(signal, index) do
    case Zoi.parse(Signal.schema(), signal) do
      {:ok, _signal} -> validate_portable(signal, [:thread, :signals, index])
      {:error, _reason} -> {:error, {:invalid_signal, index}}
    end
  end

  defp validate_portable(value, path) do
    case PortableTerm.validate(value, path) do
      :ok -> :ok
      {:error, rejected_path} -> {:error, {:nonportable, rejected_path}}
    end
  end
end
