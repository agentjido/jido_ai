defmodule JidoAI.Examples.Support.CommitCounter do
  @moduledoc "An ordinary Plugin that counts successful commits."
  use Jido.Plugin
  def state_spec(_), do: {:commits, Zoi.integer() |> Zoi.default(0)}
  def update_state(n, _, _), do: {:ok, n + 1}
end
