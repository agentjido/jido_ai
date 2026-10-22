defmodule JidoAI.Examples.ConfigureResponse.Agent do
  @moduledoc "A core Jido Agent with one static AI response configuration."

  use Jido.Agent,
    name: "configure_response_example",
    extensions: [Jido.AI.Plugin]

  ai do
    model "openai:gpt-4o-mini"
    instructions "Reply in one short sentence."
  end
end
