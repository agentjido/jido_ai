defmodule Kodo.Core.Sessions.SessionSupervisor do
  @moduledoc """
  Supervises shell sessions, allowing for multiple concurrent sessions
  with isolated state and fault tolerance.
  """
  use DynamicSupervisor

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    instance = Keyword.get(opts, :instance)
    DynamicSupervisor.start_link(__MODULE__, instance, name: name)
  end

  @doc """
  Starts a new session.
  """
  @spec new(pid() | atom(), atom() | nil) :: {:ok, String.t(), pid()} | {:error, term()}
  def new(supervisor_pid \\ __MODULE__, instance \\ nil) do
    session_id = generate_session_id()

    child_spec = %{
      id: Kodo.Core.Sessions.Session,
      start: {Kodo.Core.Sessions.Session, :start_link, [session_id]},
      restart: :transient
    }

    case DynamicSupervisor.start_child(supervisor_pid, child_spec) do
      {:ok, pid} ->
        # Register the session if we have instance info
        if instance do
          session_registry_atom = String.to_atom("Kodo.SessionRegistry.#{instance}")
          Registry.register(session_registry_atom, session_id, pid)
        end

        {:ok, session_id, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Terminates a session.
  """
  @spec stop(pid(), pid() | atom()) :: :ok | {:error, :not_found}
  def stop(pid, supervisor_pid \\ __MODULE__) when is_pid(pid) do
    DynamicSupervisor.terminate_child(supervisor_pid, pid)
  end

  @impl true
  def init(_instance) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 3,
      max_seconds: 5
    )
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end
end
