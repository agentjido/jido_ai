defmodule Jido.AI.Runtime.Plugin.Agent do
  @moduledoc false
  use Jido.Agent.Plugin

  @impl Jido.Agent.Plugin
  def state_spec(opts), do: Jido.AI.Runtime.Plugin.agent_state_spec(opts)

  @impl Jido.Agent.Plugin
  def directives(_opts), do: [Jido.AI.Configuration.Change]

  @impl Jido.Agent.Plugin
  def reduce(reduction, opts) do
    changes = Enum.filter(reduction.directives, &match?(%Jido.AI.Configuration.Change{}, &1))
    Jido.AI.Configuration.reduce(reduction.plugin_state, changes, opts)
  end
end
