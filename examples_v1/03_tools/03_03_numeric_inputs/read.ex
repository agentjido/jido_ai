defmodule JidoAI.Examples.NumericInputs.Read do
  @moduledoc "Reports the typed arguments received by a real tool Action."
  use Jido.Action,
    name: "numeric_input",
    schema:
      Zoi.object(%{
        count: Zoi.integer() |> Zoi.default(1),
        factor: Zoi.float(),
        items: Zoi.array(Zoi.object(%{count: Zoi.integer(), factor: Zoi.float()}))
      })

  def run(params, _context), do: {:ok, params}
end
