defmodule Jido.AI.Runtime.Plugin.Agent do
  @moduledoc false
  use Jido.Agent.Plugin

  @impl Jido.Agent.Plugin
  def state_spec(opts), do: Jido.AI.Runtime.Plugin.agent_state_spec(opts)

  @impl Jido.Agent.Plugin
  def directives(_opts), do: [Jido.AI.Configuration.Change]

  @impl Jido.Agent.Plugin
  def validate_directive(change, opts), do: Jido.AI.Configuration.validate(change, opts)

  @impl Jido.Agent.Plugin
  def update_state(state, directives, opts),
    do: Jido.AI.Configuration.reduce(state, directives, opts)
end
