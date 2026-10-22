defmodule JidoAI.Examples.Authoring.Support.Quote do
  @moduledoc "A reusable Flow tool with the same calculation contract as the Action."
  use Jido.Flow,
    name: "v3_example_quote",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  flow do
    step "price", action: JidoAI.Examples.Support.Multiply, params: input()
    output result("price")
  end
end
