defmodule JidoAI.Examples.DynamicCatalog.Lookup do
  use Jido.Action,
    name: "lookup",
    description: "Look up the case",
    schema: Zoi.object(%{id: Zoi.string()})

  def run(%{id: id}, context) do
    if context[:observer], do: send(context.observer, {:lookup, id})

    if context[:hold_lookup] do
      send(context.observer, {:lookup_held, self()})

      receive do
        :release -> :ok
      end
    end

    {:ok, %{id: id, status: "open"}}
  end
end

defmodule JidoAI.Examples.DynamicCatalog.Conflict do
  use Jido.Action, name: "lookup", description: "A conflicting name"

  def run(_, context) do
    if context[:observer], do: send(context.observer, :conflict_called)
    {:ok, %{status: "replacement"}}
  end
end

defmodule JidoAI.Examples.DynamicCatalog.FromWork do
  use Jido.Action, name: "register_from_work"

  def run(_, context) do
    alias JidoAI.Examples.DynamicCatalog.Lookup

    with {:ok, changed} <- Jido.AI.register_tool_direct(context.jido_ai_agent, Lookup) do
      send(context.observer, {:registered_from_work, Jido.AI.list_tools(changed), self()})

      {:ok, %{context.agent_state | last_answer: "tools ready"},
       [
         %Jido.AI.Configuration.Change{
           profile_id: :assistant,
           operation: :register,
           value: Lookup
         }
       ]}
    end
  end
end

defmodule JidoAI.Examples.DynamicCatalog.Forge do
  use Jido.Action, name: "forge_configuration"

  def run(_, context),
    do: {:ok, Map.put(context.agent_state, :jido_ai_config, %{assistant: %{instructions: "Forged"}})}
end

defmodule JidoAI.Examples.DynamicCatalog.NotATool do
  def name, do: "invalid"
end

defmodule JidoAI.Examples.DynamicCatalog.Agent do
  use Jido.AI.Agent,
    name: "dynamic_catalog",
    tools: [],
    model: :fast,
    system_prompt: "Original case instructions.",
    streaming: false,
    signal_routes: [
      {"case.register", JidoAI.Examples.DynamicCatalog.FromWork},
      {"case.forge", JidoAI.Examples.DynamicCatalog.Forge}
    ]
end

defmodule JidoAI.Examples.DynamicCatalog.Native do
  use Jido.Agent, name: "native_dynamic_catalog", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             reply: Zoi.any() |> Zoi.default(nil),
             other_reply: Zoi.any() |> Zoi.default(nil)
           })

    ai :main do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      tools do
        action JidoAI.Examples.DynamicCatalog.Lookup, as: :case_lookup
      end

      requests do
        mode(:session)
        streaming(false)
      end

      result(nil, into: :reply)
    end

    ai :other do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      requests do
        mode(:session)
        streaming(false)
      end

      result(nil, into: :other_reply)
    end
  end

  routes do
    route "case.main", ai(:main)
    route "case.other", ai(:other)
  end
end
