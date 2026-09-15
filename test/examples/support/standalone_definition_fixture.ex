defmodule JidoAI.Examples.StandaloneAuthoring.Agent do
  @moduledoc false

  def build(config, limits \\ %{timeout: 5_000, max_tool_calls: 32}) do
    Jido.AI.Reasoning.ReAct.Authoring.lower(config, limits, %{
      name: "standalone_config_example",
      schema:
        Zoi.object(%{
          result: Zoi.any() |> Zoi.default(nil),
          count: Zoi.integer() |> Zoi.default(0),
          messages: Jido.AI.Conversation.schema()
        })
    })
  end
end
