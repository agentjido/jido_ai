defmodule JidoAI.Examples.TypedSignals.Hold do
  use Jido.Action, name: "hold"

  def run(_, context) do
    send(context.observer, {:held_action, self()})

    receive do
      :release -> {:ok, %{released: true}}
    end
  end
end
