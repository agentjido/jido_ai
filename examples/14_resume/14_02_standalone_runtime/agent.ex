defmodule JidoAI.Examples.StandaloneRuntime do
  @moduledoc "The public standalone API owns an Agent through the shared v3 Session."

  def run(query, config, context) do
    Jido.AI.Reasoning.ReAct.run(query, config,
      context: context,
      limits: %{timeout: 5_000, max_tool_calls: 32}
    )
  end
end
