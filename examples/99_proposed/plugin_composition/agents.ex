defmodule JidoAI.Examples.PluginComposition.ExplicitAgent do
  @moduledoc "A core Jido Agent with the AI Plugin added explicitly."

  use Jido.Agent,
    name: "explicit_ai_plugin_example",
    plugins: [Jido.AI.Agent.Plugin]

  ai do
    model :fast
    instructions "Reply in one short sentence."
  end
end

defmodule JidoAI.Examples.PluginComposition.ConvenienceAgent do
  @moduledoc "The equivalent Agent made with the Jido AI wrapper."

  use Jido.AI.Agent, name: "convenience_ai_plugin_example"

  ai do
    model :fast
    instructions "Reply in one short sentence."
  end
end
