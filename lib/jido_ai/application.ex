defmodule Jido.AI.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    with {:ok, supervisor} <-
           Supervisor.start_link(
             [Jido.AI.Telemetry.CorrelationStore],
             strategy: :one_for_one,
             name: Jido.AI.Supervisor
           ) do
      Jido.AI.Telemetry.attach_default_handlers()
      {:ok, supervisor}
    end
  end
end
