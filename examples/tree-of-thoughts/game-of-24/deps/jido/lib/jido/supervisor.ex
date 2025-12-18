defmodule Jido.Supervisor do
  @moduledoc """
  A helper supervisor that starts and manages the resources for a specific Jido instance.

  Each consumer of Jido defines their own module:

      defmodule MyApp.Jido do
        use Jido, otp_app: :my_app
      end

  Then in your application’s supervision tree:

      children = [
        MyApp.Jido
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  """
  use Supervisor
  require Logger

  @spec start_link(module(), keyword()) :: Supervisor.on_start()
  def start_link(jido_module, config) do
    name = Keyword.get(config, :name, jido_module)

    Logger.debug(
      "Starting Jido.Supervisor for #{inspect(jido_module)} with name: #{inspect(name)}"
    )

    Supervisor.start_link(__MODULE__, {jido_module, config}, name: name)
  end

  @impl true
  def init({jido_module, _config}) do
    Logger.debug("Initializing Jido.Supervisor for #{inspect(jido_module)}")

    children = [
      {Registry, keys: :unique, name: registry_name(jido_module)},

      # Example: A dynamic supervisor to manage agent processes:
      {DynamicSupervisor, name: agent_supervisor_name(jido_module), strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp registry_name(jido_module), do: Module.concat(jido_module, "Registry")
  defp agent_supervisor_name(jido_module), do: Module.concat(jido_module, "AgentSupervisor")
end
