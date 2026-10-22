defmodule JidoAI.Examples.CallCounts.HeldInput do
  @behaviour Jido.AI.Control
  def check(_, %{hold_input: true, observer: observer}) do
    send(observer, {:input_held, self()})

    receive do
      :release -> :ok
    end
  end

  def check(input, context), do: JidoAI.Examples.CallCounts.Input.check(input, context)
end
