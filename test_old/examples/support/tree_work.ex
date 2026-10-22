defmodule JidoAI.Examples.ToT.Work do
  use Jido.Action, name: "tree_work", schema: Zoi.object(%{n: Zoi.integer()})

  def run(%{n: n}, context) do
    send(context.observer, {:tree_work, n, self()})

    if context[:hold_tools],
      do:
        (receive do
           :release -> :ok
         end)

    send(context.observer, {:tree_work_finished, n})
    {:ok, %{n: n}}
  end
end
