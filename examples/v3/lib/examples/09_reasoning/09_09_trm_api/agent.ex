defmodule JidoAI.Examples.TRMAPI.Public do
  use Jido.AI.TRMAgent, name: "public_recursive", model: :example
end

defmodule JidoAI.Examples.TRMAPI.Default do
  use Jido.AI.TRMAgent, name: "default_recursive"
end

defmodule JidoAI.Examples.TRMAPI.Custom do
  use Jido.AI.TRMAgent,
    name: "custom_recursive",
    description: "Custom recursive reasoning",
    model: :example,
    max_supervision_steps: 2,
    act_threshold: 0.99,
    system_prompt: "Use the supplied facts",
    streaming: false,
    max_tokens: 70,
    temperature: 0.3,
    llm_opts: [max_tokens: 90, temperature: 0.4]
end

defmodule JidoAI.Examples.TRMAPI.Bounded do
  use Jido.AI.TRMAgent,
    name: "bounded_recursive",
    model: :example,
    max_supervision_steps: 4,
    max_iterations: 2
end

defmodule JidoAI.Examples.TRMAPI.Common do
  use Jido.AI.Agent,
    name: "common_recursive",
    model: :example,
    reasoning: :trm,
    reasoning_options: [max_supervision_steps: 1]
end
