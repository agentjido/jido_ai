defmodule Jido.AI.Configuration.Plugin.AgentServer do
  @moduledoc false
  @behaviour Jido.Plugin

  @impl Jido.Plugin
  def admit(_runtime_ref, admission, opts),
    do: {:ok, %{options: opts, agent_module: admission.agent_module}}
end
