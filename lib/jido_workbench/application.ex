defmodule JidoWorkbench.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    config = Application.fetch_env!(:jido_workbench, :agent_jido)

    jido_opts = [
      id: config[:agent_id]
    ]

    # Room configuration
    room_opts = [
      id: config[:room_id],
      name: "Jido Chat Room",
      strategy: Jido.Chat.Room.Strategy.FreeForm
    ]

    children = [
      # Start the LLM Keys manager first
      JidoWorkbench.LLMKeys,
      # Start the Telemetry supervisor
      JidoWorkbenchWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: JidoWorkbench.PubSub},
      # Start Finch
      {Finch, name: JidoWorkbench.Finch},
      # Start the Endpoint (http/https)
      JidoWorkbenchWeb.Endpoint,
      # Start the GitHub Stars Tracker
      {JidoWorkbench.GithubStarsTracker, []},
      # Jido Task Supervisor
      {Task.Supervisor, name: JidoWorkbench.TaskSupervisor},

      # Jido
      # Start the Jido Agent
      {JidoWorkbench.AgentJido, jido_opts}
      # Start the Jido Chat Room
      # {JidoWorkbench.ChatRoom, room_opts}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: JidoWorkbench.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JidoWorkbenchWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
