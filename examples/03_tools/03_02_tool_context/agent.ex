defmodule JidoAI.Examples.ToolContext.Read do
  use Jido.Action, name: "read_context", schema: Zoi.object(%{})

  def run(_, context) do
    if context[:observe_identity] do
      send(context.observer, {
        :tool_identity,
        Map.take(context, [:agent_id, :agent_module, :agent_state, :state])
      })
    end

    if context[:hold_context] do
      send(context.observer, {:context_held, self()})

      receive do
        :release -> :ok
      after
        5_000 -> raise "context barrier timed out"
      end
    end

    visible =
      Map.take(context, [:tenant, :region, :request_only, :secret, "tenant", "request_only"])

    send(context.observer, {:tool_context, visible, context[:agent_id]})
    {:ok, visible}
  end
end

for {module, mode} <- [
      {JidoAI.Examples.ToolContext.SnapshotSession, :session},
      {JidoAI.Examples.ToolContext.SnapshotTurn, :turn}
    ] do
  defmodule module do
    use Jido.Agent, name: "tool_state_snapshot", extensions: [Jido.AI.DSL]
    @mode mode

    agent do
      schema Zoi.object(%{
               reply: Zoi.any() |> Zoi.default(nil),
               counter: Zoi.integer() |> Zoi.default(7)
             })

      ai :assistant do
        tool_context(%{tenant: "native"})

        models do
          model(:answer, :example)
        end

        reasoning :react do
          model(:answer)
        end

        requests do
          mode(@mode)
          streaming(false)
        end

        tools do
          action JidoAI.Examples.ToolContext.Read,
            as: :read_context,
            forward_context: [
              :observer,
              :observe_identity,
              :agent_id,
              :agent_module,
              :agent_state,
              :state,
              :tenant
            ]
        end

        result(nil, into: :reply)
      end
    end

    routes do
      route "context.assistant", ai(:assistant)
    end
  end
end

defmodule JidoAI.Examples.ToolContext.Public do
  use Jido.AI.Agent,
    name: "context_defaults",
    model: :example,
    tools: [JidoAI.Examples.ToolContext.Read],
    tool_context: %{tenant: "base", region: "us"},
    streaming: false

  @impl true
  def before_tool_call(call, context) do
    send(context.observer, {:before_context, Map.take(context, [:tenant, :region])})
    {:ok, call}
  end
end

defmodule JidoAI.Examples.ToolContext.Native do
  use Jido.Agent, name: "native_tool_context", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      tool_context(%{tenant: "native", secret: "private"})

      models do
        model(:answer, :example)
      end

      reasoning :react do
        model(:answer)
      end

      tools do
        action JidoAI.Examples.ToolContext.Read,
          as: :read_context,
          forward_context: [:tenant, :observer]
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "context.assistant", ai(:assistant)
  end
end
