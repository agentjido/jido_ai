defmodule Jido.AI.Execution.PendingInput do
  @moduledoc false
  alias Jido.AI.Orchestration.ExecutionBridge

  def seal(context), do: ExecutionBridge.input(context, :seal)

  def seal_if_empty(context) do
    ExecutionBridge.input(context, :seal_if_empty) |> queue_result(context)
  end

  def drain(state, context) do
    result =
      case ExecutionBridge.input(context, :drain) |> queue_result(context) do
        {:ok, _} = result -> result
        {:error, reason} -> {:error, {:pending_input_server, reason}}
      end

    with {:ok, items} <- result, do: consume(state, items, context)
  end

  defp queue_result({:error, _} = error, context) do
    {:ok, _} = ExecutionBridge.report(context, {:failure_type, :runtime})
    error
  end

  defp queue_result(result, _), do: result

  defp consume(state, [], _context), do: {:ok, state}

  defp consume(state, items, context) do
    {:ok, %{request_id: id, run_id: run_id}} = ExecutionBridge.request(context)

    entries =
      Enum.flat_map(items, fn item ->
        refs =
          %{request_id: id, run_id: run_id}
          |> Map.merge(item.refs || %{})
          |> Map.put(:source, item.source)

        Jido.AI.Orchestration.Transcript.query(item.content, refs)
      end)

    with {:ok, state} <- Jido.AI.Orchestration.Transcript.record(state, entries, context) do
      Enum.reduce_while(Enum.zip(items, entries), {:ok, state}, fn {item, entry}, {:ok, state} ->
        case ExecutionBridge.report(
               context,
               {:event, :input_injected,
                %{
                  input_id: item.id,
                  content: item.content,
                  source: item.source,
                  refs: item.refs,
                  at_ms: item.at_ms
                }}
             ) do
          {:ok, _} ->
            message =
              Jido.AI.Model.Messages.put_refs(
                ReqLLM.Context.user(item.content),
                Jido.AI.Orchestration.Transcript.request_refs(context, entry.refs)
              )

            messages = ReqLLM.Context.append(state.messages, message)
            {:cont, {:ok, %{state | messages: messages}}}

          error ->
            {:halt, error}
        end
      end)
    end
  end
end
