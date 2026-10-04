defmodule Jido.AI.Plugins.Retrieval.Agent do
  @moduledoc false
  def state_spec(opts), do: Jido.AI.Plugins.Retrieval.agent_state_spec(opts)

  def prepare(preparation, opts), do: Jido.AI.Plugins.Retrieval.prepare_input(preparation, opts)
end
