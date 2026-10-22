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
