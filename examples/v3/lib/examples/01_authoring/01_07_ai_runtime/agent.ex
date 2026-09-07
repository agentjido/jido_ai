defmodule JidoAI.Examples.AIRuntime.Audit do
  @moduledoc "An ordinary Plugin that counts successful commits."
  use Jido.Plugin
  def state_spec(_), do: {:commits, Zoi.integer() |> Zoi.default(0)}
  def update_state(n, _, _), do: {:ok, n + 1}
end

defmodule JidoAI.Examples.AIRuntime.Close do
  @moduledoc false
  use Jido.Action, name: "ai_example_close", schema: Zoi.object(%{reason: Zoi.string()})
  def run(%{reason: reason}, %{agent_state: state}), do: {:ok, %{state | case_id: reason}}
end

defmodule JidoAI.Examples.AIRuntime.Record do
  @moduledoc "Records a control call without changing work input."
  @behaviour Jido.AI.Control
  def check(value, context) do
    send(context.observer, {:control_checked, value})
    :ok
  end
end

defmodule JidoAI.Examples.AIRuntime.Reject do
  @moduledoc false
  @behaviour Jido.AI.Control
  def check(_, _), do: Jido.AI.Profile.error("example.policy", "Rejected")
end

defmodule JidoAI.Examples.AIRuntime.WaitTool do
  @moduledoc "A tool with a test-controlled completion barrier."
  use Jido.Action, name: "ai_example_wait", schema: Zoi.object(%{n: Zoi.integer()}, coerce: true)

  def run(%{n: n}, context) do
    send(context.observer, {:tool_waiting, self(), n})

    receive do
      :release -> {:ok, %{value: n}}
    end
  end
end

defmodule JidoAI.Examples.AIRuntime.WaitControl do
  @moduledoc false
  @behaviour Jido.AI.Control
  def check(_, context) do
    send(context.observer, {:control_waiting, self()})

    receive do
      :release -> :ok
    end
  end
end

defmodule JidoAI.Examples.AIRuntime.Agent do
  @moduledoc "01_07: The AI DSL composes with ordinary routes and Plugin-owned state."
  use Jido.Agent, name: "ai_runtime_example", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             reply: Zoi.map() |> Zoi.default(%{}),
             case_id: Zoi.string() |> Zoi.default("case-42")
           })

    plugin JidoAI.Examples.AIRuntime.Audit

    ai :assistant do
      instructions("Use the tool results.")

      models do
        model :answer, JidoAI.Examples.MockLLM.model() do
          generation(temperature: 0.2)
        end
      end

      reasoning :react do
        model(:answer)
        tool_concurrency(2)
      end

      tools do
        action JidoAI.Examples.ToolFlow.Multiply, as: :multiply, forward_context: [:observer]
        flow(JidoAI.Examples.ToolFlow.Quote, as: :quote, forward_context: [:observer])
      end

      controls do
        max_iterations 4
        max_model_calls(5)
        max_tool_calls(8)
        timeout(5_000)
        input(JidoAI.Examples.AIRuntime.Record)
        model(JidoAI.Examples.AIRuntime.Record)
        operation(JidoAI.Examples.AIRuntime.Record)
        output JidoAI.Examples.AIRuntime.Record
      end

      result(Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)}), into: :reply, max_repairs: 1)
    end
  end

  routes do
    signal_source "/examples/ai/runtime"

    route "ai.ask", ai(:assistant) do
      define :answer, args: [:query]
    end

    route "case.close", JidoAI.Examples.AIRuntime.Close do
      define :close, args: [:reason]
    end
  end
end
