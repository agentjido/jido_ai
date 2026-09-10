defmodule Jido.AI.Runtime.Plugin.AgentServer do
  @moduledoc false
  use Jido.AgentServer.Plugin

  @impl Jido.AgentServer.Plugin
  def admit(_runtime_ref, command, opts) do
    Jido.AI.Runtime.Plugin.prepare_command(command, opts)
  end
end
