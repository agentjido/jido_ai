defmodule JidoAI.Examples.TerminalState.Control do
  @behaviour Jido.AI.Control
  def check(_, context) do
    case context[:failure] do
      nil -> :ok
      reason -> {:error, reason}
    end
  end
end
