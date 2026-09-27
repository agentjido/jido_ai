defmodule Jido.AI.Plugins.Retrieval.AgentServer do
  @moduledoc false
  use Jido.AgentServer.Plugin

  @impl Jido.AgentServer.Plugin
  defdelegate admit(runtime, admission, opts), to: Jido.AI.Plugins.Retrieval
end
