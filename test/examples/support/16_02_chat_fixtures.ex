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
        {Jido.AI.Plugins.Chat, Keyword.put_new(config, :tools, %{"label" => JidoAI.Examples.Chat.Echo})}
      ],
      routes: Jido.AI.Plugins.Chat.signal_routes(config)
    })
  end

  def signal(route, params),
    do: Jido.Signal.new!("chat." <> route, params, source: "/examples/chat")

  def tool(id \\ "call_label", label \\ "ready"),
    do: %{id: id, name: "label", arguments: %{"label" => label}}
end
