defmodule JidoAI.Examples.BasicAgent.Agent do
  @moduledoc "A core Jido Agent with one static AI configuration."

  use Jido.AI.Agent, name: "basic_ai_agent_example"

  ai do
    model :fast
    instructions "Reply in one short sentence."
  end
end
