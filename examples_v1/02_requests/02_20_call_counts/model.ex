defmodule JidoAI.Examples.CallCounts.Model do
  @behaviour Jido.AI.Control
  def check(_, %{reject_at: :model}), do: {:error, :model_rejected}
  def check(_, _), do: :ok
end
