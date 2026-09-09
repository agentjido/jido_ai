defmodule JidoAI.Examples.AuthoringFormats.Flow do
  @moduledoc "A model result becomes complete Agent state at the last step."
  use Jido.Flow, name: "v3_example_authoring", schema: JidoAI.Examples.Schema.prompt()

  flow do
    step "model", action: JidoAI.Examples.Generate, params: %{query: input(:query)}
    step "candidate", action: JidoAI.Examples.Commit, params: result("model")
    output result("candidate")
  end
end

defmodule JidoAI.Examples.AuthoringFormats.Agent do
  @moduledoc "01_01: Core authoring forms use the same Flow and live commit."
  use Jido.Agent, name: "v3_example_authoring_agent"

  agent do
    schema JidoAI.Examples.Schema.state()
  end

  routes do
    signal_source "/examples/ai"

    route "ai.ask", JidoAI.Examples.AuthoringFormats.Flow do
      define :answer, args: [:query]
    end
  end
end
