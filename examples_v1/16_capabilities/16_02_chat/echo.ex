defmodule JidoAI.Examples.Chat.Echo do
  use Jido.Action,
    name: "echo",
    description: "Return a supplied label",
    schema: Zoi.object(%{label: Zoi.string(), count: Zoi.integer() |> Zoi.default(1)})

  def run(params, _context) do
    {:ok, params}
  end
end
