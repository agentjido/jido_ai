defmodule JidoAI.Examples.StreamActivity.Probe do
  @moduledoc "A real tool with an observable lifetime and permitted retries."
  use Jido.Action, name: "stream_probe", schema: Zoi.object(%{n: Zoi.integer()})

  def run(%{n: n}, context) do
    attempt =
      Agent.get_and_update(
        context.counter,
        &{Map.get(&1, n, 0) + 1, Map.update(&1, n, 1, fn v -> v + 1 end)}
      )

    send(context.observer, {:activity_tool, n, attempt, self()})

    if context[:retry] == true and attempt == 1 do
      {:error, Jido.Action.Error.execution_error("Try again", %{retry: true})}
    else
      if context[:release_after],
        do: Process.send_after(self(), {:release, :ok}, context.release_after)

      receive do
        {:release, :ok} ->
          {:ok, %{n: n, attempt: attempt}}

        {:release, :error} ->
          {:error, Jido.Action.Error.execution_error("Tool failed", %{retry: false})}
      end
    end
  end
end

defmodule JidoAI.Examples.StreamActivity.Agent do
  @moduledoc "Public request helpers use the core-owned tool work and one event owner."
  use Jido.AI.Agent,
    name: "stream_activity_example",
    tools: [JidoAI.Examples.StreamActivity.Probe],
    model: :example,
    stream_timeout_ms: 300,
    tool_heartbeat_ms: 25,
    tool_timeout_ms: 2_000,
    tool_max_retries: 1,
    tool_retry_backoff_ms: 120
end

defmodule JidoAI.Examples.StreamActivity.DefaultAgent do
  @moduledoc false
  use Jido.AI.Agent,
    name: "default_stream_activity_example",
    tools: [JidoAI.Examples.StreamActivity.Probe],
    model: :example,
    tool_timeout_ms: 2_000
end

defmodule JidoAI.Examples.StreamActivity.NativeAgent do
  @moduledoc "Native requests declare idle and heartbeat intervals in milliseconds."
  use Jido.Agent, name: "native_stream_activity_example", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
        tool_concurrency(2)
      end

      tools do
        action JidoAI.Examples.StreamActivity.Probe,
          as: :stream_probe,
          timeout: 2_000,
          max_retries: 1,
          retry_backoff: 120,
          forward_context: [:observer, :counter, :release_after, :retry]
      end

      requests do
        mode(:session)
        streaming(true)
        steering(true)
        idle_timeout(300)
        tool_heartbeat(25)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
  end
end
