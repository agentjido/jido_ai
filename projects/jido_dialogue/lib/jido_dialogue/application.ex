defmodule Jido.Dialogue.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: Jido.Dialogue.Worker.start_link(arg)
      # {Jido.Dialogue.Worker, arg}
      {Jido.Dialogue.Supervisor, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Jido.Dialogue.ApplicationSupervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    # Store the supervisor PID in the application environment
    Application.put_env(:jido_dialogue, :supervisor_pid, pid)

    {:ok, pid}
  end

  @impl true
  def start_phase(:start_test_app, _start_type, _phase_args) do
    :ok
  end
end
