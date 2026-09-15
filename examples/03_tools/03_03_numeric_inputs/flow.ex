defmodule JidoAI.Examples.NumericInputs.Flow do
  @moduledoc "The same tool input contract applies to a callable Flow."
  use Jido.Flow,
    name: "numeric_input_flow",
    schema: JidoAI.Examples.NumericInputs.Read.schema()

  flow do
    step "read", action: JidoAI.Examples.NumericInputs.Read, params: input()
    output result("read")
  end
end
