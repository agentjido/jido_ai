defmodule Jido.AI.Plugins.Planning.Agent do
  @moduledoc false
  def state_spec(opts), do: Jido.AI.Plugins.Planning.agent_state_spec(opts)

  def prepare(preparation, opts), do: Jido.AI.Plugins.Planning.prepare_input(preparation, opts)
end
