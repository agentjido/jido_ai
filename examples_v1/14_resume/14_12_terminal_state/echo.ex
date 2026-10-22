defmodule JidoAI.Examples.TerminalState.Echo do
  use Jido.Action,
    name: "terminal_echo",
    description: "Report one real tool call",
    schema: Zoi.object(%{value: Zoi.integer()})

  def run(%{value: value}, _context) do
    {:ok, %{value: value}}
  end
end
