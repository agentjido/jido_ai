defmodule Jido.AI.Runtime.NextBatch do
  @moduledoc false
  use Jido.Action, name: "ai_next_batch", schema: Jido.AI.Runtime.State.schema()

  @impl Jido.Action
  def run(state, context), do: Jido.AI.Error.capture(fn -> execute(state, context) end)

  defp execute(%{pending_batches: [batch | rest]} = state, _) do
    {:continue, %{state | batch: batch, pending_batches: rest}, Jido.AI.Runtime.ToolsFlow}
  end

  defp execute(state, context) do
    with {:ok, state} <- Jido.AI.Runtime.ToolInterception.finish_all(state, context),
         results =
           Enum.map(state.tool_results, fn result ->
             ReqLLM.Context.tool_result(result.id, result.name, result.content)
             |> Jido.AI.Model.Messages.put_refs(
               Jido.AI.Session.Transcript.request_refs(context, Map.get(result, :refs, %{}))
             )
           end),
         {:ok, messages} <-
           ReqLLM.Context.append_tool_exchange(state.response.context, state.response, results),
         entries =
           Enum.zip_with(Jido.AI.Model.Messages.entries(results), state.tool_results, fn entry, result ->
             Map.put(entry, :refs, Map.get(result, :refs, %{}))
           end),
         {:ok, state} <- Jido.AI.Session.Transcript.record(state, entries, context),
         {:ok, state} <- Jido.AI.Runtime.ToolCycle.record(%{state | messages: messages}, context),
         {:ok, state} <- Jido.AI.Runtime.Checkpoint.consume_queries(state, context),
         {:ok, state} <-
           Jido.AI.Runtime.Checkpoint.pause(
             state,
             :after_tools,
             context
           ) do
      {:continue, state, Jido.AI.Runtime.ReasonFlow}
    else
      {:error, reason} -> Jido.AI.Runtime.OutputState.fail(state, reason, context)
    end
  end
end
