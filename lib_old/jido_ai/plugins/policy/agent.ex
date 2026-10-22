defmodule Jido.AI.Plugins.Policy.Agent do
  @moduledoc false
  @behaviour Jido.Plugin

  @impl Jido.Plugin
  def state_spec(opts), do: Jido.AI.Plugins.Policy.agent_state_spec(opts)

  @impl Jido.Plugin
  def prepare(preparation, _opts), do: Jido.AI.Plugins.Policy.prepare_input(preparation)
end
