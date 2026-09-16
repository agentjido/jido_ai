defmodule JidoAI.Examples.ToolFlow.Receipt do
  @moduledoc "Returns a price and separate direct-caller receipt data."
  use Jido.Action,
    name: "price_with_receipt",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  def run(%{a: a, b: b}, _context) do
    {:ok, %{value: a * b}, [%{receipt: "DIRECT_CALLER_ONLY"}]}
  end
end

defmodule JidoAI.Examples.ToolFlow.ReceiptFlow do
  @moduledoc "A Flow tool consumes the price, not the Action's direct-caller extras."
  use Jido.Flow,
    name: "price_flow",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  flow do
    step "price", action: JidoAI.Examples.ToolFlow.Receipt, params: input()
    output result("price")
  end
end
