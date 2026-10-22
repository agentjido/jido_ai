defmodule Jido.AI.Plugins.Chat.Agent do
  @moduledoc false
  @behaviour Jido.Plugin

  @impl Jido.Plugin
  def state_spec(opts), do: Jido.AI.Plugins.Chat.agent_state_spec(opts)

  @impl Jido.Plugin
  def prepare(preparation, opts), do: Jido.AI.Plugins.Chat.prepare_input(preparation, opts)
end
