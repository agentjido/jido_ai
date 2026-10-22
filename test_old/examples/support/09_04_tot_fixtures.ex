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

defmodule JidoAI.Examples.ToT do
  alias JidoAI.Examples.ToT.Agent

  def source do
    Agent |> Jido.AI.Agent.profile(:assistant) |> Map.from_struct()
  end

  def base do
    %{
      name: Agent.definition().name,
      module: Agent,
      vsn: Agent.vsn(),
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
    {:ok, %{tools: %{"tree_work" => JidoAI.Examples.ToT.Work}, llm_opts: [tool_choice: "required"]}}
  end
end
