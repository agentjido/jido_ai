defmodule JidoAI.Examples.PromptPolicy.Default do
  use Jido.AI.AdaptiveAgent,
    name: "prompt_default",
    model: :example,
    available_strategies: [:react],
    streaming: false
end

defmodule JidoAI.Examples.PromptPolicy.Nil do
  use Jido.AI.AdaptiveAgent,
    name: "prompt_nil",
    model: :example,
    available_strategies: [:react],
    system_prompt: nil,
    streaming: false
end

defmodule JidoAI.Examples.PromptPolicy.False do
  use Jido.AI.AdaptiveAgent,
    name: "prompt_false",
    model: :example,
    available_strategies: [:react],
    system_prompt: false,
    streaming: false
end

defmodule JidoAI.Examples.PromptPolicy.Empty do
  use Jido.AI.AdaptiveAgent,
    name: "prompt_empty",
    model: :example,
    available_strategies: [:react],
    system_prompt: "",
    streaming: false
end

defmodule JidoAI.Examples.PromptPolicy.Custom do
  @prompt "Use the supplied case facts."
  use Jido.AI.AdaptiveAgent,
    name: "prompt_custom",
    model: :example,
    available_strategies: [:react],
    system_prompt: @prompt,
    streaming: false
end

defmodule JidoAI.Examples.PromptPolicy.Common do
  use Jido.AI.Agent,
    name: "prompt_common",
    model: :example,
    reasoning: :adaptive,
    reasoning_options: %{available_strategies: [:react]},
    streaming: false
end
