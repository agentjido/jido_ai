defmodule JidoAI.Examples.ToolLimits.Agent do
  @moduledoc "Declare a per-tool attempt budget inside a bounded request."
  use Jido.AI.Agent, name: "tool_limit_example"

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      model "openai:gpt-4o-mini"
      instructions "Use multiply and return its result."

      observability do
        store_content true
      end

      tools do
        action JidoAI.Examples.Support.Multiply,
          as: :multiply,
          timeout: 1_000,
          max_retries: 1,
          retry_backoff: 150
      end

      controls do
        timeout 5_000
        max_model_calls 2
        max_tool_calls 1
      end

      requests do
        mode :session
      end

      result into: :reply
    end
  end

  routes do
    signal_source "/examples/ai/02_requests/02_13"

    route "examples.ai.02_13.calculate", ai: :assistant do
      define :calculate, args: [:query]
    end
  end
end
