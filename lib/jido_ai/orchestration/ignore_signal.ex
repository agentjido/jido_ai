defmodule Jido.AI.Orchestration.IgnoreSignal do
  @moduledoc false
  use Jido.Action, name: "ai_ignore_unhandled_observation"
  def run(_, context), do: {:ok, context.agent_state}
end
