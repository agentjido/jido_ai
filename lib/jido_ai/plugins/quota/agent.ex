defmodule Jido.AI.Plugins.Quota.Agent do
  @moduledoc false
  def state_spec(opts), do: Jido.AI.Plugins.Quota.agent_state_spec(opts)

  def prepare(preparation, opts), do: Jido.AI.Plugins.Quota.prepare_input(preparation, opts)
end
