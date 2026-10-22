defmodule JidoAI.Examples.ToT.Check do
  @behaviour Jido.AI.Control
  def check(_result, context) do
    if context[:reject], do: {:error, context.reject}, else: :ok
  end
end
