defmodule JidoAI.Examples.EarlyToolActivity.WriteDocument do
  @moduledoc "Writes a complete, validated model document through a real Action."
  use Jido.Action, name: "write_document", schema: Zoi.object(%{body: Zoi.string() |> Zoi.min(1)})

  def run(%{body: body}, context) do
    send(context.observer, {:document_started, body})

    with :ok <- File.write(context.output_path, body),
         do: {:ok, %{bytes: byte_size(body), written: true}}
  end
end

defmodule JidoAI.Examples.EarlyToolActivity.Control do
  @moduledoc false
  @behaviour Jido.AI.Control
  def check(_, context),
    do: if(context[:block_document], do: {:error, :document_blocked}, else: :ok)
end

defmodule JidoAI.Examples.EarlyToolActivity.Agent do
  @moduledoc "Delta capture can be disabled without stopping provider activity or tool execution."
  use Jido.Agent, name: "early_tool_activity", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      observability(%{emit_llm_deltas?: true})

      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      controls do
        operation(JidoAI.Examples.EarlyToolActivity.Control)
      end

      tools do
        action JidoAI.Examples.EarlyToolActivity.WriteDocument,
          as: :write_document,
          forward_context: [:observer, :output_path]
      end

      requests do
        mode(:session)
        streaming(true)
        idle_timeout(300)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
  end
end

defmodule JidoAI.Examples.EarlyToolActivity.QuietAgent do
  @moduledoc "The legacy public delta flag also controls runtime delta capture."
  use Jido.AI.Agent,
    name: "quiet_early_tool_activity",
    tools: [JidoAI.Examples.EarlyToolActivity.WriteDocument],
    model: :example,
    stream_timeout_ms: 300,
    observability: %{emit_llm_deltas?: false}
end
