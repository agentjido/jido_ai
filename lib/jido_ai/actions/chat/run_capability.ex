defmodule Jido.AI.Actions.Chat.RunCapability do
  @moduledoc "Runs a declared Chat capability and returns a complete Agent state."
  use Jido.Action, name: "chat_run_capability", schema: Zoi.map()

  def run(params, %{agent_state: _} = context) do
    case Jido.AI.Capability.prepared(context, Jido.AI.Plugins.Chat) do
      %{action: action} = binding -> Jido.AI.Capability.run(action, params, context, binding)
      _ -> {:error, :chat_capability_not_bound}
    end
  end

  def run(_, _), do: {:error, :chat_capability_not_bound}
end
