defmodule JidoAI.Examples.Streaming.Generate do
  @moduledoc "SSE output is transient. Only the complete answer reaches the next step."
  use Jido.Action, name: "v3_example_stream", schema: JidoAI.Examples.Schema.prompt()

  def run(%{query: query}, context) do
    with {:ok, stream} <-
           Jido.AI.Runtime.ModelCall.request(:stream, context.model, query, context.model_options) do
      send(context.observer, {:stream_opened, stream})

      try do
        answer =
          stream
          |> ReqLLM.StreamResponse.tokens()
          |> Enum.map_join(fn token ->
            send(context.observer, {:token, token})
            token
          end)

        {:ok, %{answer: answer}}
      after
        ReqLLM.StreamResponse.close(stream)
      end
    end
  end
end

defmodule JidoAI.Examples.Streaming.Flow do
  @moduledoc false
  use Jido.Flow, name: "v3_example_stream_flow", schema: JidoAI.Examples.Schema.prompt()

  flow do
    step "stream", action: JidoAI.Examples.Streaming.Generate, params: input()
    step "candidate", action: JidoAI.Examples.Commit, params: result("stream")
    output result("candidate")
  end
end

defmodule JidoAI.Examples.Streaming.Agent do
  @moduledoc "01_05: Progress before one final live commit."
  use Jido.Agent, name: "v3_example_stream_agent"

  agent do
    schema JidoAI.Examples.Schema.state()
  end

  routes do
    route "ai.ask", JidoAI.Examples.Streaming.Flow
  end
end
