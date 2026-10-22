defmodule JidoAI.Examples.CallCounts.Input do
  @behaviour Jido.AI.Control
  def check(_, %{reject_at: :input}), do: {:error, :input_rejected}

  def check(_, _), do: :ok
end
