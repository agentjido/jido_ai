defmodule JidoAI.Examples.StandaloneInput do
  @moduledoc "A caller supplies its input queue to the common standalone Agent runtime."

  def run(query, config, jido, observer) do
    Jido.AI.Reasoning.ReAct.run(query, config,
      context: %{jido: jido, observer: observer},
      limits: %{timeout: 5_000, max_tool_calls: 32}
    )
  end
end

defmodule JidoAI.Examples.StandaloneInput.Repair do
  @moduledoc "Hold local output repair after the input queue has closed."

  def fix(_, _, _, context) do
    send(context.observer, {:input_sealed_repair, self()})

    receive do
      :release -> {:ok, %{answer: "Fixed"}}
    end
  end
end
