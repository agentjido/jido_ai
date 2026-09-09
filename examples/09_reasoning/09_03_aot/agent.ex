defmodule JidoAI.Examples.AoT.Check do
  @behaviour Jido.AI.Control
  def check(result, context) do
    send(context.observer, {:aot_checked, result})
    if context[:reject], do: {:error, context.reject}, else: :ok
  end
end

defmodule JidoAI.Examples.AoT.Agent do
  use Jido.Agent, name: "aot_puzzle", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :algorithm_of_thoughts do
        model(:answer)
        options(profile: :short, search_style: :dfs)
      end

      controls do
        output(JidoAI.Examples.AoT.Check)
      end

      requests do
        mode(:session)
        streaming(true)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.aot.query", ai(:assistant)
  end
end

defmodule JidoAI.Examples.AoT.Public do
  use Jido.AI.AoTAgent, name: "public_aot", model: :example
end

defmodule JidoAI.Examples.AoT.Custom do
  use Jido.AI.AoTAgent,
    name: "custom_aot",
    model: :example,
    profile: :long,
    search_style: :bfs,
    examples: ["  one example  ", ""],
    require_explicit_answer: false,
    temperature: 0.3,
    max_tokens: 99,
    llm_opts: [max_tokens: 101]
end

defmodule JidoAI.Examples.AoT.Repair do
  def repair(_output, _raw, _reason), do: {:ok, %{value: 24}}

  def repair(output, raw, reason, context) do
    send(context.observer, {:aot_repair, output, raw, reason})
    {:ok, %{value: 24}}
  end
end

defmodule JidoAI.Examples.AoT do
  alias JidoAI.Examples.AoT.Agent

  def puzzle do
    """
    Trying a promising first operation:
    1. 8 - 6 : (4,4,2)
    - 4 + 2 : (6,4) 24 = 6 * 4 -> found it!
    Backtracking the solution:
    Step 1: 8 - 6 = 2
    Step 2: 4 + 2 = 6
    Step 3: 6 * 4 = 24
    answer: (4 + (8 - 6)) * 4 = 24
    """
  end

  def source do
    {_, config} = Enum.find(Agent.definition().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    Map.from_struct(config[:profiles].assistant)
  end

  def base do
    %{
      name: Agent.definition().name,
      module: Agent,
      vsn: Agent.vsn(),
      schema: Agent.domain_schema(),
      routes: [{"ai.aot.query", Jido.AI.Authoring.ai(:assistant)}]
    }
  end

  def definition(changes \\ %{}),
    do: Jido.AI.Authoring.lower(base(), [Map.merge(source(), changes)])
end

defmodule JidoAI.Examples.AoT.LegacyValues do
  use Jido.AI.AoTAgent,
    name: "legacy_aot_values",
    model: :example,
    examples: [:example, 24, " ", nil],
    temperature: "invalid"
end
