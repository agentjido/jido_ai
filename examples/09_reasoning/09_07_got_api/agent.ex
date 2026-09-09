defmodule JidoAI.Examples.GoTAPI.Public do
  use Jido.AI.GoTAgent, name: "public_graph", model: :example
end

defmodule JidoAI.Examples.GoTAPI.Custom do
  use Jido.AI.GoTAgent,
    name: "custom_graph",
    description: "Custom graph search",
    model: :example,
    max_nodes: 8,
    max_depth: 2,
    aggregation_strategy: :weighted,
    generation_prompt: "Generate from these facts",
    connection_prompt: "Connect these facts",
    aggregation_prompt: "Summarize these facts",
    streaming: false,
    max_tokens: 70,
    temperature: 0.3,
    llm_opts: [max_tokens: 90, temperature: 0.4]
end

defmodule JidoAI.Examples.GoTAPI.Deep do
  use Jido.AI.GoTAgent,
    name: "deep_graph",
    model: :example,
    max_nodes: 11,
    max_depth: 20,
    min_nodes_for_aggregation: 100
end

defmodule JidoAI.Examples.GoTAPI.Common do
  use Jido.AI.Agent,
    name: "common_graph",
    model: :example,
    reasoning: :graph_of_thoughts,
    reasoning_options: [max_depth: 1]
end
