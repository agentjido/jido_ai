defmodule Jido.AI.Actions.Chat.RunCapability do
  @moduledoc "Runs a declared Chat capability and returns a complete Agent state."
  use Jido.Action, name: "chat_run_capability", schema: Zoi.map()

  def run(
        params,
        %{jido_ai_chat_capability: %{action: action} = binding, agent_state: _} = context
      ),
      do: Jido.AI.Capability.run(action, params, context, binding)

  def run(_, _), do: {:error, :chat_capability_not_bound}
end
