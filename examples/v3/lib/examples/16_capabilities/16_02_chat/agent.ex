defmodule JidoAI.Examples.Chat.Echo do
  use Jido.Action,
    name: "echo",
    description: "Return a supplied label",
    schema: Zoi.object(%{label: Zoi.string(), count: Zoi.integer() |> Zoi.default(1)})

  def run(params, context) do
    if context[:observer], do: send(context.observer, {:chat_echo, params})
    {:ok, params}
  end
end

defmodule JidoAI.Examples.Chat.Telemetry do
  def handle(event, measurements, metadata, %{observer: observer, id: id}) do
    if metadata[:request_id] == id,
      do: send(observer, {:chat_telemetry, event, measurements, metadata})
  end
end

defmodule JidoAI.Examples.Chat.EchoFlow do
  use Jido.Flow,
    name: "echo_flow",
    description: "Return a supplied label through a Flow",
    schema: Zoi.object(%{label: Zoi.string()})

  flow do
    step("label", action: JidoAI.Examples.Chat.Echo, params: input())
    output(result("label"))
  end
end

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
    route "case.set", JidoAI.Examples.ReasoningCapabilities.SetCase
  end
end

defmodule JidoAI.Examples.Chat do
  @moduledoc "Seven Chat capability routes share one ordinary core Agent."

  def definition(config \\ []) do
    Jido.Agent.new(%{
      name: "chat_capability",
      schema:
        Zoi.object(%{
          result: Zoi.any() |> Zoi.default(nil),
          case_id: Zoi.string() |> Zoi.default("case-17")
        }),
      plugins: [
        {Jido.AI.Plugins.Chat,
         Keyword.put_new(config, :tools, %{"label" => JidoAI.Examples.Chat.Echo})}
      ],
      routes: Jido.AI.Plugins.Chat.signal_routes(config)
    })
  end

  def signal(route, params),
    do: Jido.Signal.new!("chat." <> route, params, source: "/examples/chat")

  def tool(id \\ "call_label", label \\ "ready"),
    do: %{id: id, name: "label", arguments: %{"label" => label}}
end
