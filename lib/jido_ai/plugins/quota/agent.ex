defmodule Jido.AI.Plugins.Quota.Agent do
  @moduledoc false
  @behaviour Jido.Plugin

  @impl Jido.Plugin
  def state_spec(opts), do: Jido.AI.Plugins.Quota.agent_state_spec(opts)

  @impl Jido.Plugin
  def prepare(preparation, opts), do: Jido.AI.Plugins.Quota.prepare_input(preparation, opts)
end
