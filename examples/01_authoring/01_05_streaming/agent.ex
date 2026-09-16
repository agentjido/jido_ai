defmodule JidoAI.Examples.Streaming.Agent do
  @moduledoc "A session streams request events and commits only a complete answer."
  use Jido.AI.Agent, name: "v3_example_stream_agent"

  agent do
    schema Zoi.object(%{
             answer: Zoi.string() |> Zoi.default(""),
             case_id: Zoi.string() |> Zoi.default("case-42")
           })

    ai :assistant do
      model "openai:gpt-4o-mini"
      instructions "Give a short answer."

      controls do
        timeout 5_000
        max_model_calls 1
      end

      result into: :answer
    end
  end

  routes do
    signal_source "/examples/ai/01_authoring/01_05"

    route "examples.ai.01_05.answer", ai: :assistant do
      define :answer, args: [:query]
    end
  end
end
