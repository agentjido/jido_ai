defmodule Jido.AI.Plugins.Quota.AgentServer do
  @moduledoc false
  @behaviour Jido.Plugin

  @impl Jido.Plugin
  def admit(_runtime, admission, _opts), do: Jido.AI.Plugins.Quota.admit_input(admission)
end
