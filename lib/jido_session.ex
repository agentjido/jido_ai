defmodule Jido.Session do
  @moduledoc """
  An immutable, portable conversation value.

  A Session owns conversation identity, lifecycle state, one Thread, and
  metadata. It does not own a process, a model request, or storage.
  """

  alias Jido.{PortableTerm, Signal, Thread}

  @enforce_keys [:id, :thread]
  defstruct id: nil, status: :open, thread: nil, metadata: %{}

  @type status :: :open | :closed
  @type t :: %__MODULE__{
          id: String.t(),
          status: status(),
          thread: Thread.t(),
          metadata: map()
        }

  @doc "Creates an open Session."
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ [])

  def new(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs), do: new(Map.new(attrs)), else: {:error, :invalid_session_options}
  end

  def new(attrs) when is_map(attrs) and not is_struct(attrs) do
    with :ok <- known_keys(attrs, [:id, :thread, :metadata]),
         id = Map.get_lazy(attrs, :id, &Signal.ID.generate!/0),
         {:ok, thread} <- thread(Map.get(attrs, :thread)),
         metadata = Map.get(attrs, :metadata, %{}),
         :ok <- validate_id(id),
         :ok <- validate_metadata(metadata) do
      {:ok, %__MODULE__{id: id, thread: thread, metadata: metadata}}
    end
  end

  def new(_attrs), do: {:error, :invalid_session_options}

  @doc "Creates an open Session or raises."
  @spec new!(keyword() | map()) :: t() | no_return()
  def new!(attrs \\ []) do
    case new(attrs) do
      {:ok, session} -> session
      {:error, reason} -> raise ArgumentError, "invalid Session: #{inspect(reason)}"
    end
  end

  @doc "Appends one Signal to the open Session."
  @spec append(t(), Signal.t()) :: {:ok, t()} | {:error, term()}
  def append(%__MODULE__{status: :closed}, _signal), do: {:error, :session_closed}

  def append(%__MODULE__{} = session, signal) do
    with :ok <- validate(session),
         {:ok, thread} <- Thread.append(session.thread, signal) do
      {:ok, %{session | thread: thread}}
    end
  end

  def append(_session, _signal), do: {:error, :invalid_session}

  @doc "Appends a Signal batch atomically to the open Session."
  @spec append_many(t(), [Signal.t()]) :: {:ok, t()} | {:error, term()}
  def append_many(%__MODULE__{status: :closed}, _signals), do: {:error, :session_closed}

  def append_many(%__MODULE__{} = session, signals) do
    with :ok <- validate(session),
         {:ok, thread} <- Thread.append_many(session.thread, signals) do
      {:ok, %{session | thread: thread}}
    end
  end

  def append_many(_session, _signals), do: {:error, :invalid_session}

  @doc "Closes the Session. Closing an already closed Session is a no-op."
  @spec close(t()) :: {:ok, t()} | {:error, term()}
  def close(%__MODULE__{status: :closed} = session) do
    with :ok <- validate(session), do: {:ok, session}
  end

  def close(%__MODULE__{} = session) do
    with :ok <- validate(session), do: {:ok, %{session | status: :closed}}
  end

  def close(_session), do: {:error, :invalid_session}

  @doc "Validates the complete Session value."
  @spec validate(term()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = session) do
    with :ok <- validate_id(session.id),
         :ok <- validate_status(session.status),
         :ok <- Thread.validate(session.thread),
         :ok <- validate_metadata(session.metadata) do
      validate_portable(session, [:session])
    end
  end

  def validate(_session), do: {:error, :invalid_session}

  @doc false
  def validate_schema(value, _opts) do
    case validate(value) do
      :ok -> :ok
      {:error, reason} -> {:error, "must be a valid Session: #{inspect(reason)}"}
    end
  end

  @doc "Returns a schema that accepts valid Session values."
  @spec schema() :: Zoi.schema()
  def schema, do: Zoi.any() |> Zoi.refine({__MODULE__, :validate_schema, []})

  defp known_keys(attrs, allowed) do
    case Map.keys(attrs) -- allowed do
      [] -> :ok
      keys -> {:error, {:unknown_session_options, keys}}
    end
  end

  defp thread(nil), do: Thread.new()

  defp thread(%Thread{} = thread) do
    with :ok <- Thread.validate(thread), do: {:ok, thread}
  end

  defp thread(_thread), do: {:error, :invalid_session_thread}

  defp validate_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
  defp validate_id(_id), do: {:error, :invalid_session_id}

  defp validate_status(status) when status in [:open, :closed], do: :ok
  defp validate_status(_status), do: {:error, :invalid_session_status}

  defp validate_metadata(metadata) when is_map(metadata) and not is_struct(metadata),
    do: validate_portable(metadata, [:session, :metadata])

  defp validate_metadata(_metadata), do: {:error, :invalid_session_metadata}

  defp validate_portable(value, path) do
    case PortableTerm.validate(value, path) do
      :ok -> :ok
      {:error, rejected_path} -> {:error, {:nonportable, rejected_path}}
    end
  end
end
