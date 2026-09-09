defmodule JidoAI.Examples.Linear.CheckAnswer do
  @behaviour Jido.AI.Control
  def check(answer, context) do
    send(context.observer, {:answer_checked, answer})

    cond do
      context[:rejection] -> {:error, context.rejection}
      context[:expected] && context.expected != answer -> {:error, :wrong_answer}
      true -> :ok
    end
  end
end

defmodule JidoAI.Examples.Linear.CoT do
  use Jido.Agent, name: "linear_cot", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :chain_of_thought do
        model(:answer)
      end

      controls do
        output JidoAI.Examples.Linear.CheckAnswer
      end

      requests do
        mode(:session)
        streaming(true)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
  end
end

defmodule JidoAI.Examples.Linear.CoD do
  use Jido.Agent, name: "linear_cod", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :chain_of_draft do
        model(:answer)
      end

      controls do
        output JidoAI.Examples.Linear.CheckAnswer
      end

      requests do
        mode(:session)
        streaming(true)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
  end
end

defmodule JidoAI.Examples.Linear.PublicCoT do
  use Jido.AI.CoTAgent, name: "public_cot", model: :example
end

defmodule JidoAI.Examples.Linear.PublicCoD do
  use Jido.AI.CoDAgent, name: "public_cod", model: :example
end

defmodule JidoAI.Examples.Linear.PublicMedia do
  use Jido.AI.CoTAgent, name: "public_media", model: :example, streaming: false
end

defmodule JidoAI.Examples.Linear.Telemetry do
  def handle(event, measurements, metadata, observer),
    do: send(observer, {:linear_telemetry, event, measurements, metadata})
end

defmodule JidoAI.Examples.Linear.PublicLimits do
  use Jido.AI.CoTAgent,
    name: "linear_limits",
    model: :example,
    llm_timeout_ms: 100,
    request_timeout_ms: 2_000,
    max_tokens: 17,
    llm_opts: [max_tokens: 23]
end

defmodule JidoAI.Examples.Linear.PublicDeadline do
  use Jido.AI.CoDAgent,
    name: "linear_deadline",
    model: :example,
    llm_timeout_ms: 1_000,
    request_timeout_ms: 300
end
