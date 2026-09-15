defmodule JidoAI.Examples.InitialState.Echo do
  use Jido.Action,
    name: "import_echo",
    description: "Report any new tool execution",
    schema: Zoi.object(%{value: Zoi.integer()})

  def run(%{value: value}, _context) do
    {:ok, %{value: value}}
  end
end
