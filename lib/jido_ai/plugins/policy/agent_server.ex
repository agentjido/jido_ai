defmodule Jido.AI.Plugins.Policy.AgentServer do
  @moduledoc false
  use Jido.AgentServer.Plugin

  @impl Jido.AgentServer.Plugin
  def admit(_runtime, admission, _opts), do: Jido.AI.Plugins.Policy.admit_input(admission)

  @impl Jido.AgentServer.Plugin
  def prepare_dispatch(_runtime, signal, context, _opts),
    do: Jido.AI.Plugins.Policy.prepare_dispatch(signal, context.plugin_state)
end
