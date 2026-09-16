defmodule JidoAI.Examples.StandaloneAuthoring do
  @moduledoc "Configure standalone tool work with explicit application limits."
  alias Jido.AI.Reasoning.ReAct

  def config(options \\ []) do
    defaults = [
      model: "openai:gpt-4o-mini",
      system_prompt: "Use multiply for arithmetic.",
      tools: %{"multiply" => JidoAI.Examples.Support.Multiply},
      stream_content: true,
      store_content: true,
      max_iterations: 2,
      max_tokens: 256,
      tool_timeout_ms: 1_000,
      tool_max_retries: 0,
      tool_concurrency: 1
    ]

    ReAct.Config.new(Keyword.merge(defaults, options))
  end

  def run(query, config, context) do
    ReAct.run(query, config,
      context: context,
      limits: %{timeout: 5_000, max_tool_calls: 1}
    )
  end
end
