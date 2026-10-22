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
    Agent |> Jido.AI.Agent.profile(:assistant) |> Map.from_struct()
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

defmodule JidoAI.Examples.AoT.RequestTransformer do
  @moduledoc "Adds one fresh request header to each model call."
  @behaviour Jido.AI.Reasoning.ReAct.RequestTransformer

  def transform_request(request, _state, _config, context) do
    n = Agent.get_and_update(context.calls, &{&1 + 1, &1 + 1})

    http =
      request.llm_opts
      |> Keyword.get(:req_http_options, [])
      |> Keyword.put(:headers, [{"x-credential-version", Integer.to_string(n)}])

    {:ok, %{llm_opts: [req_http_options: http]}}
  end
end
