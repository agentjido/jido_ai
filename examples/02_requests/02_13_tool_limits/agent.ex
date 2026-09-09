defmodule JidoAI.Examples.ToolLimits.Probe do
  @moduledoc "A real tool can wait until its owner releases or stops it."
  use Jido.Action, name: "timed_probe", schema: Zoi.object(%{n: Zoi.integer()})

  def run(%{n: n}, context) do
    attempt =
      Elixir.Agent.get_and_update(
        context.counter,
        &{Map.get(&1, n, 0) + 1, Map.update(&1, n, 1, fn v -> v + 1 end)}
      )

    started = System.monotonic_time(:millisecond)
    send(context.observer, {:probe_started, n, attempt, self(), started})

    if context[:probe_mode] == :hold do
      receive do
        :release -> :ok
      end
    end

    if context[:probe_mode] == :retry, do: Process.sleep(60)

    if context[:probe_mode] == :retry and attempt == 1,
      do: {:error, Jido.Action.Error.timeout_error("Tool permits retry", %{retry: true})},
      else: {:ok, %{n: n, attempt: attempt, elapsed_ms: System.monotonic_time(:millisecond) - started}}
  end
end

defmodule JidoAI.Examples.ToolLimits.ProbeFlow do
  @moduledoc false
  use Jido.Flow, name: "timed_probe_flow", schema: Zoi.object(%{n: Zoi.integer()})

  flow do
    step "probe", action: JidoAI.Examples.ToolLimits.Probe, params: input()
    output result("probe")
  end
end

defmodule JidoAI.Examples.ToolLimits.Rewrite do
  @moduledoc false
  @behaviour Jido.AI.ToolInterceptor
  def before_tool_call(call, context) do
    send(context.observer, {:prepared, call.id})

    if context[:rewrite],
      do: {:ok, %{call | arguments: Map.update!(call.arguments, "n", &(&1 + 1))}},
      else: {:ok, call}
  end
end

defmodule JidoAI.Examples.ToolLimits.Control do
  @moduledoc false
  @behaviour Jido.AI.Control
  def check(call, context) do
    send(context.observer, {:native_preflight, call.id, call.arguments})

    if context[:native_block] == call.id do
      case context[:native_result] do
        :interrupt -> {:interrupt, %{kind: :approval, message: "Approval required"}}
        _ -> {:error, :native_blocked}
      end
    else
      :ok
    end
  end
end

defmodule JidoAI.Examples.ToolLimits.Agent do
  @moduledoc "The full prepared batch is checked before real tools start."
  use Jido.Agent, name: "tool_limit_example", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      tool_interceptor(JidoAI.Examples.ToolLimits.Rewrite)

      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
        tool_concurrency(2)
      end

      controls do
        operation(JidoAI.Examples.ToolLimits.Control)
      end

      tools do
        action JidoAI.Examples.ToolLimits.Probe,
          as: :timed_probe,
          timeout: 45_000,
          max_retries: 1,
          retry_backoff: 150,
          forward_context: [:observer, :counter, :probe_mode]

        flow(JidoAI.Examples.ToolLimits.ProbeFlow,
          as: :timed_flow,
          timeout: 45_000,
          forward_context: [:observer, :counter, :probe_mode]
        )
      end

      requests do
        mode(:session)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
  end
end
