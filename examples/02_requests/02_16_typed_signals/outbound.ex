defmodule JidoAI.Examples.TypedSignals.Outbound do
  use Jido.Plugin, agent_server: __MODULE__.AgentServer

  defmodule AgentServer do
    @moduledoc false
    use Jido.AgentServer.Plugin

    def prepare_dispatch(_, signal, context, _) do
      if context.turn_context[:reject_delivery],
        do: {:error, :delivery_rejected},
        else: {:ok, %{signal | subject: "version-#{context.state_version}"}}
    end
  end
end
