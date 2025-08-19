defmodule JidoEval.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize component registry and register built-in metrics
    :ok = Jido.Eval.ComponentRegistry.start_link()
    :ok = Jido.Eval.Metrics.register_all()

    children = [
      # Registry for tracking evaluation runs
      {Registry,
       keys: :unique, name: Jido.Eval.Engine.Registry, partitions: System.schedulers_online()},

      # Task supervisor for evaluation runs
      {Task.Supervisor, name: Jido.Eval.Engine.TaskSupervisor, strategy: :one_for_one}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: JidoEval.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
