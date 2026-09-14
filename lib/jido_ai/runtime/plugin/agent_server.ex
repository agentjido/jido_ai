defmodule Jido.AI.Runtime.Plugin.AgentServer do
  @moduledoc false
  use Jido.AgentServer.Plugin

  @impl Jido.AgentServer.Plugin
  def admit(_runtime_ref, admission, opts),
    do: {:ok, %{options: opts, agent_module: admission.agent_module}}
end
