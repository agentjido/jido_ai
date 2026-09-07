defmodule JidoAI.Examples.ToT.Check do
  @behaviour Jido.AI.Control
  def check(result, context) do
    send(context.observer, {:tot_checked, result})
    if context[:reject], do: {:error, context.reject}, else: :ok
  end
end

defmodule JidoAI.Examples.ToT.Work do
  use Jido.Action, name: "tree_work", schema: Zoi.object(%{n: Zoi.integer()})

  def run(%{n: n}, context) do
    send(context.observer, {:tree_work, n, self()})

    if context[:hold_tools],
      do:
        (receive do
           :release -> :ok
         end)

    send(context.observer, {:tree_work_finished, n})
    {:ok, %{n: n}}
  end
end

defmodule JidoAI.Examples.ToT.Hooks do
  @behaviour Jido.AI.ToolInterceptor
  def before_tool_call(call, context) do
    send(context.observer, {:tree_before, call.id})
    {:ok, %{call | arguments: %{"n" => String.to_integer(call.arguments["n"])}}}
  end

  def after_tool_call(call, {:ok, %{n: n}, effects}, context) do
    send(context.observer, {:tree_after, call.id, n})
    {:ok, {:ok, %{n: n + 100}, effects}}
  end
end

defmodule JidoAI.Examples.ToT.Agent do
  use Jido.Agent, name: "tree_search", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :tree_of_thoughts do
        model(:answer)
        options(branching_factor: 2, max_depth: 1)
      end

      controls do
        output(JidoAI.Examples.ToT.Check)
      end

      requests do
        mode(:session)
        streaming(true)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.tot.query", ai(:assistant)
  end
end

defmodule JidoAI.Examples.ToT do
  alias JidoAI.Examples.ToT.Agent

  def source do
    {_, config} = Enum.find(Agent.agent().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    Map.from_struct(config[:profiles].assistant)
  end

  def base do
    %{
      name: Agent.agent().name,
      module: Agent,
      schema: Agent.domain_schema(),
      routes: [{"ai.tot.query", Jido.AI.Authoring.ai(:assistant)}]
    }
  end

  def definition(changes \\ %{}),
    do: Jido.AI.Authoring.lower(base(), [Map.merge(source(), changes)])

  def options(value),
    do: %{
      reasoning: %{source().reasoning | options: Map.merge(source().reasoning.options, value)}
    }

  def thoughts(values), do: Jason.encode!(%{thoughts: values})
  def scores(values), do: Jason.encode!(%{scores: values})

  def script do
    [
      %{reply: {:text, thoughts(["First path", "Better path"])}},
      %{reply: {:text, scores(%{t1: 0.4, t2: 0.8})}}
    ]
  end
end

defmodule JidoAI.Examples.ToT.Transform do
  def transform_request(_request, _state, _config, _context) do
    {:ok,
     %{tools: %{"tree_work" => JidoAI.Examples.ToT.Work}, llm_opts: [tool_choice: "required"]}}
  end
end
