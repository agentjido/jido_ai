defmodule JidoAI.Examples.AdaptiveAPI.Public do
  use Jido.AI.AdaptiveAgent,
    name: "public_adaptive",
    model: :example,
    tools: [JidoAI.Examples.ToT.Work],
    method_options: %{tot: %{branching_factor: 2, max_depth: 1}}
end

defmodule JidoAI.Examples.AdaptiveAPI.Default do
  use Jido.AI.AdaptiveAgent, name: "default_adaptive"
end

defmodule JidoAI.Examples.AdaptiveAPI.Custom do
  use Jido.AI.AdaptiveAgent,
    name: "custom_adaptive",
    description: "Custom method selection",
    model: :example,
    default_strategy: :tot,
    available_strategies: [:cot, :trm],
    strategy_override: :trm,
    complexity_thresholds: %{simple: 0.1, complex: 0.9},
    method_options: %{trm: %{max_supervision_steps: 2, act_threshold: 0.99}},
    system_prompt: "Use the supplied facts",
    streaming: false,
    max_tokens: 70,
    temperature: 0.3,
    llm_opts: [max_tokens: 90, temperature: 0.4]
end

defmodule JidoAI.Examples.AdaptiveAPI.Bounded do
  use Jido.AI.AdaptiveAgent,
    name: "bounded_adaptive",
    model: :example,
    available_strategies: [:trm],
    max_iterations: 2
end

defmodule JidoAI.Examples.AdaptiveAPI.CoT do
  use Jido.AI.AdaptiveAgent,
    name: "cot_adaptive",
    model: :example,
    default_strategy: :react,
    available_strategies: [:cot]
end

defmodule JidoAI.Examples.AdaptiveAPI.AoT do
  use Jido.AI.AdaptiveAgent,
    name: "aot_adaptive",
    model: :example,
    available_strategies: [:aot, :tot]
end

defmodule JidoAI.Examples.AdaptiveAPI.Common do
  use Jido.AI.Agent,
    name: "common_adaptive",
    model: :example,
    reasoning: :adaptive,
    reasoning_options: %{available_strategies: [:cod]}
end

defmodule JidoAI.Examples.AdaptiveAPI.Typed do
  use Jido.AI.AdaptiveAgent,
    name: "typed_adaptive",
    model: :example,
    available_strategies: [:cod, :aot],
    output: [
      schema: Zoi.object(%{value: Zoi.integer()}),
      on_validation_error: :repair,
      retries: 1
    ]
end

defmodule JidoAI.Examples.AdaptiveAPI.Hooks do
  use Jido.AI.AdaptiveAgent,
    name: "adaptive_hooks",
    model: :example,
    tools: [JidoAI.Examples.ToT.Work],
    method_options: %{tot: %{branching_factor: 2, max_depth: 1}}

  @impl true
  def before_tool_call(call, context),
    do: JidoAI.Examples.ToT.Hooks.before_tool_call(call, context)

  @impl true
  def after_tool_call(call, result, context),
    do: JidoAI.Examples.ToT.Hooks.after_tool_call(call, result, context)
end
