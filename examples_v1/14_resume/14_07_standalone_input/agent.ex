defmodule JidoAI.Examples.StandaloneInput do
  @moduledoc "A caller supplies its input queue to the common standalone Agent runtime."

  def run(query, config, context) do
    Jido.AI.Reasoning.ReAct.run(query, config,
      context: context,
      limits: %{timeout: 5_000, max_tool_calls: 32}
    )
  end
end
