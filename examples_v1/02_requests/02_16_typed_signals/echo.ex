defmodule JidoAI.Examples.TypedSignals.Echo do
  use Jido.Action, name: "echo", schema: Zoi.object(%{value: Zoi.string()})

  def run(params, _context) do
    {:ok, %{echo: params.value}}
  end
end
