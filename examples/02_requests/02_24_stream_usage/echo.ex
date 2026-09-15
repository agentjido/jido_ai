defmodule JidoAI.Examples.StreamUsage.Echo do
  @moduledoc "A real tool used to separate usage from two model calls."
  use Jido.Action, name: "usage_echo", schema: Zoi.object(%{n: Zoi.integer()})

  def run(%{n: n}, _context) do
    {:ok, %{n: n}}
  end
end
