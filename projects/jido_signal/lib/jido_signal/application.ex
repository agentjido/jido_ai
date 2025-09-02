defmodule Jido.Signal.Application do
  @moduledoc """
  The main application module for Jido Signal.

  This module handles the initialization and supervision of the signal processing
  infrastructure, including the Registry and Task Supervisor.
  """
  use Application

  @doc """
  Starts the Jido Signal application.

  Initializes the supervision tree with the Registry for managing signal subscriptions
  and a Task Supervisor for handling asynchronous operations.

  ## Parameters

  - `_type`: The application start type (ignored)
  - `_args`: Application start arguments (ignored)

  ## Returns

  `{:ok, pid}` where pid is the supervisor process ID
  """
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Jido.Signal.Registry},

      # Extension Registry for Signal extensions
      Jido.Signal.Ext.Registry,

      # Exec Async Actions Task Supervisor
      {Task.Supervisor, name: Jido.Signal.TaskSupervisor}
    ]

    opts = [strategy: :one_for_one, name: Jido.Signal.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
