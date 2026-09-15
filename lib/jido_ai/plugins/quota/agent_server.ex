defmodule Jido.AI.Plugins.Quota.AgentServer do
  @moduledoc false
  use Jido.AgentServer.Plugin

  @impl Jido.AgentServer.Plugin
  def admit(_runtime, admission, _opts), do: Jido.AI.Plugins.Quota.admit_input(admission)
end
