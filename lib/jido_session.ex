defmodule Jido.Session do
  @moduledoc """
  A portable interaction session that owns one `Jido.Thread`.

  A Session can span many AI requests. It does not own a process, live request,
  stream, Plugin, AgentServer, or persistence adapter. `Jido.AI.Orchestration` owns
  the live AI request API.
  """

  alias Jido.Thread

  @version 1
  @schema Zoi.struct(
            __MODULE__,
            %{
              version: Zoi.integer(description: "Portable format version") |> Zoi.default(@version),
              id: Zoi.string(description: "Unique session identifier") |> Zoi.min(1),
              rev: Zoi.integer(description: "Monotonic session revision") |> Zoi.min(0) |> Zoi.default(0),
              thread: Thread.schema(),
              status: Zoi.enum([:open, :closed]) |> Zoi.default(:open),
              created_at: Zoi.integer(description: "Creation timestamp in milliseconds"),
              updated_at: Zoi.integer(description: "Last update timestamp in milliseconds"),
              metadata: Zoi.map(description: "Portable metadata") |> Zoi.default(%{})
            },
            coerce: true,
            unrecognized_keys: :error
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Session schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates an open session with one thread."
  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    now = Keyword.get(opts, :now, System.system_time(:millisecond))
    id = Keyword.get(opts, :id, "session_#{Jido.Util.generate_id()}")

    thread =
      Keyword.get_lazy(opts, :thread, fn -> Thread.new(id: "#{id}:thread", now: now) end)

    %__MODULE__{
      version: @version,
      id: id,
      rev: thread.rev,
      thread: thread,
      status: :open,
      created_at: now,
      updated_at: now,
      metadata: Keyword.get(opts, :metadata, %{})
    }
    |> validate!()
  end

  @doc "Builds an open session around an existing thread."
  @spec from_thread(Thread.t(), keyword()) :: t()
  def from_thread(%Thread{} = thread, opts \\ []) do
    id = Keyword.get(opts, :id, "session:#{thread.id}")

    %__MODULE__{
      version: @version,
      id: id,
      rev: thread.rev,
      thread: thread,
      status: :open,
      created_at: Keyword.get(opts, :created_at, thread.created_at),
      updated_at: Keyword.get(opts, :updated_at, thread.updated_at),
      metadata: Keyword.get(opts, :metadata, %{})
    }
    |> validate!()
  end

  @doc "Appends entries to the owned thread and returns the complete next session."
  @spec append(t(), Thread.Entry.t() | map() | [Thread.Entry.t() | map()] | nil) :: t()
  def append(%__MODULE__{status: :closed}, _entries),
    do: raise(ArgumentError, "cannot append to a closed session")

  def append(%__MODULE__{} = session, entries) when entries in [nil, []], do: session

  def append(%__MODULE__{} = session, entries) do
    thread = Thread.append(session.thread, entries)

    %{
      session
      | rev: session.rev + (thread.rev - session.thread.rev),
        thread: thread,
        updated_at: thread.updated_at
    }
    |> validate!()
  end

  @doc "Replaces all session metadata with a portable map."
  @spec put_metadata(t(), map()) :: t()
  def put_metadata(%__MODULE__{} = session, metadata) when is_map(metadata) do
    case Jido.Action.validate_static_data(metadata) do
      :ok ->
        %{session | rev: session.rev + 1, metadata: metadata, updated_at: now_after(session.updated_at)}
        |> validate!()

      {:error, _} ->
        raise ArgumentError, "invalid session metadata"
    end
  end

  @doc "Closes the session. Closing an already closed session has no effect."
  @spec close(t()) :: t()
  def close(%__MODULE__{status: :closed} = session), do: session

  def close(%__MODULE__{} = session) do
    %{session | rev: session.rev + 1, status: :closed, updated_at: now_after(session.updated_at)}
    |> validate!()
  end

  @doc "Returns true when the session accepts new entries."
  @spec open?(t()) :: boolean()
  def open?(%__MODULE__{status: status}), do: status == :open

  @doc "Returns a portable versioned Session map."
  @spec encode(t()) :: map()
  def encode(%__MODULE__{} = session) do
    validate!(session)

    %{
      "type" => "jido.session",
      "version" => @version,
      "id" => session.id,
      "rev" => session.rev,
      "thread" => Thread.encode(session.thread),
      "status" => Atom.to_string(session.status),
      "created_at" => session.created_at,
      "updated_at" => session.updated_at,
      "metadata" => session.metadata
    }
  end

  @doc "Decodes and validates a portable Session map."
  @spec decode(t() | map()) :: {:ok, t()} | {:error, :invalid_session | :unsupported_version}
  def decode(%__MODULE__{} = session), do: validate(session)

  def decode(map) when is_map(map) do
    with :ok <- document_version(map),
         true <- known_keys?(map),
         {:ok, thread} <- Thread.decode(field(map, :thread)),
         status when status in [:open, :closed] <- decode_status(field(map, :status)),
         session = %__MODULE__{
           version: @version,
           id: field(map, :id),
           rev: field(map, :rev) || 0,
           thread: thread,
           status: status,
           created_at: field(map, :created_at),
           updated_at: field(map, :updated_at),
           metadata: field(map, :metadata) || %{}
         },
         {:ok, session} <- validate(session) do
      {:ok, session}
    else
      {:error, :unsupported_version} = error -> error
      _ -> {:error, :invalid_session}
    end
  end

  def decode(_), do: {:error, :invalid_session}

  @doc false
  @spec validate(t()) :: {:ok, t()} | {:error, :invalid_session}
  def validate(%__MODULE__{} = session) do
    with {:ok, _} <- Zoi.parse(@schema, session),
         true <- session.version == @version,
         true <- session.rev >= session.thread.rev,
         true <- session.updated_at >= session.created_at,
         {:ok, _} <- Thread.validate(session.thread),
         :ok <- Jido.Action.validate_static_data(session.metadata) do
      {:ok, session}
    else
      _ -> {:error, :invalid_session}
    end
  end

  def validate(_), do: {:error, :invalid_session}

  defp validate!(session) do
    case validate(session) do
      {:ok, session} -> session
      {:error, :invalid_session} -> raise ArgumentError, "invalid session"
    end
  end

  defp document_version(map) do
    case {field(map, :type), field(map, :version)} do
      {"jido.session", @version} -> :ok
      _ -> {:error, :unsupported_version}
    end
  end

  defp known_keys?(map) do
    keys = ~w(type version id rev thread status created_at updated_at metadata __struct__)
    allowed = keys ++ Enum.map(keys, &String.to_atom/1)
    Map.keys(map) -- allowed == []
  end

  defp decode_status(:open), do: :open
  defp decode_status(:closed), do: :closed
  defp decode_status("open"), do: :open
  defp decode_status("closed"), do: :closed
  defp decode_status(_), do: nil
  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp now_after(previous), do: max(System.system_time(:millisecond), previous)
end
