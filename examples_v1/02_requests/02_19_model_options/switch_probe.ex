defmodule JidoAI.Examples.ModelOptions.SwitchProbe do
  @moduledoc "A real tool separates model requests during a provider change."
  use Jido.Action, name: "switch_probe", schema: Zoi.object(%{n: Zoi.integer()})

  def run(%{n: n}, _context) do
    {:ok, %{n: n}}
  end
end
