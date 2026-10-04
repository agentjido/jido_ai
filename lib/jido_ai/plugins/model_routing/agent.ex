defmodule Jido.AI.Plugins.ModelRouting.Agent do
  @moduledoc false
  def state_spec(opts), do: Jido.AI.Plugins.ModelRouting.agent_state_spec(opts)

  def prepare(preparation, _opts), do: Jido.AI.Plugins.ModelRouting.prepare_input(preparation)
end
