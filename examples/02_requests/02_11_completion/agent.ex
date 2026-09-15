defmodule JidoAI.Examples.Completion.Agent do
  @moduledoc "Commit an AI answer and portable receipt effects in one core transition."
  use Jido.AI.Agent, name: "completion_example"

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})
    plugin JidoAI.Examples.Completion.Receipts

    ai :assistant do
      model "openai:gpt-4o-mini"
      instructions "Record the receipt, then summarize the result."
      effect_policy(%{allow: [JidoAI.Examples.Completion.Receipt]})

      reasoning :react do
        effect_policy(%{allow: [JidoAI.Examples.Completion.Receipt]})
      end

      tools do
        action JidoAI.Examples.Completion.RecordReceipt, as: :record_receipt
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
    signal_source "/examples/ai/02_requests/02_11"

    route "examples.ai.02_11.complete", ai: :assistant do
      define :complete, args: [:query]
    end
  end
end
