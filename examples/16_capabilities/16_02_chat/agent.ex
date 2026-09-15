defmodule JidoAI.Examples.Chat.Agent do
  use Jido.Agent, name: "chat_capability_dsl"

  agent do
    schema Zoi.object(%{
             result: Zoi.any() |> Zoi.default(nil),
             case_id: Zoi.string() |> Zoi.default("case-17")
           })

    plugin Jido.AI.Plugins.Chat,
      config: [into: :result, tools: %{"label" => JidoAI.Examples.Chat.Echo}]
  end

  routes do
    route "chat.message", Jido.AI.Actions.Chat.RunCapability
    route "chat.simple", Jido.AI.Actions.Chat.RunCapability
    route "chat.complete", Jido.AI.Actions.Chat.RunCapability
    route "chat.embed", Jido.AI.Actions.Chat.RunCapability
    route "chat.generate_object", Jido.AI.Actions.Chat.RunCapability
    route "chat.execute_tool", Jido.AI.Actions.Chat.RunCapability
    route "chat.list_tools", Jido.AI.Actions.Chat.RunCapability
    route "case.set", JidoAI.Examples.Support.SetCase
  end
end
