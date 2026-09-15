defmodule Jido.AI.Plugins.Planning.Agent do
  @moduledoc false
  use Jido.Agent.Plugin

  @impl Jido.Agent.Plugin
  def state_spec(opts), do: Jido.AI.Plugins.Planning.agent_state_spec(opts)

  @impl Jido.Agent.Plugin
  def prepare(preparation, opts), do: Jido.AI.Plugins.Planning.prepare_input(preparation, opts)
end
