defmodule Jido.AI.Plugins.Retrieval.AgentServer do
  @moduledoc false
  use Jido.AgentServer.Plugin

  @impl Jido.AgentServer.Plugin
  def admit(_runtime, admission, _opts), do: Jido.AI.Plugins.Retrieval.admit_input(admission)
end
