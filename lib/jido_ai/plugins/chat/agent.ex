defmodule Jido.AI.Plugins.Chat.Agent do
  @moduledoc false
  def state_spec(opts), do: Jido.AI.Plugins.Chat.agent_state_spec(opts)

  def prepare(preparation, opts), do: Jido.AI.Plugins.Chat.prepare_input(preparation, opts)
end
