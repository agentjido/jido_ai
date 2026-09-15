defmodule Jido.AI.Plugins.Chat.Agent do
  @moduledoc false
  use Jido.Agent.Plugin

  @impl Jido.Agent.Plugin
  def state_spec(opts), do: Jido.AI.Plugins.Chat.agent_state_spec(opts)

  @impl Jido.Agent.Plugin
  def prepare(preparation, opts), do: Jido.AI.Plugins.Chat.prepare_input(preparation, opts)
end
