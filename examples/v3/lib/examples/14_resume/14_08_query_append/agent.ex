defmodule JidoAI.Examples.QueryAppend do
  @moduledoc "Append input to a saved standalone run through its native Agent and Flow."

  def run(token, query, config, opts) do
    with {:ok, next} <-
           Jido.AI.Reasoning.ReAct.continue(token, config, Keyword.put(opts, :query, query)),
         do: Jido.AI.Reasoning.ReAct.collect_stream(next.events)
  end
end
