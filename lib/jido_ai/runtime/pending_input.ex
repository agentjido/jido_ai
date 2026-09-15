defmodule Jido.AI.Runtime.PendingInput do
  @moduledoc false
  alias Jido.AI.{PendingInputServer, Session}

  def seal(context) do
    case context[:jido_ai_input_queue] do
      nil -> :ok
      queue -> PendingInputServer.seal(queue)
    end
  end

  def seal_if_empty(context) do
    case context[:jido_ai_input_queue] do
      nil -> :sealed
      queue -> PendingInputServer.seal_if_empty(queue) |> queue_result(context)
    end
  end

  def drain(state, context) do
    result =
      case context[:jido_ai_input_queue] do
        nil ->
          {:ok, []}

        queue ->
          case PendingInputServer.drain_result(queue) |> queue_result(context) do
            {:ok, _} = result -> result
            {:error, reason} -> {:error, {:pending_input_server, reason}}
          end
      end

    with {:ok, items} <- result, do: consume(state, items, context)
  end

  defp queue_result({:error, _} = error, context) do
    :ok = Session.failure_type(context, :runtime)
    error
  end

  defp queue_result(result, _), do: result

  defp consume(state, [], _context), do: {:ok, state}

  defp consume(state, items, context) do
    {_, id, run_id} = context.jido_ai_events

    entries =
      Enum.flat_map(items, fn item ->
        refs =
          %{request_id: id, run_id: run_id}
          |> Map.merge(item.refs || %{})
          |> Map.put(:source, item.source)

        Jido.AI.Session.Transcript.query(item.content, refs)
      end)

    with {:ok, state} <- Jido.AI.Session.Transcript.record(state, entries, context) do
      Enum.reduce_while(Enum.zip(items, entries), {:ok, state}, fn {item, entry}, {:ok, state} ->
        case Session.emit(context, :input_injected, %{
               input_id: item.id,
               content: item.content,
               source: item.source,
               refs: item.refs,
               at_ms: item.at_ms
             }) do
          :ok ->
            message =
              Jido.AI.Model.Messages.put_refs(
                ReqLLM.Context.user(item.content),
                Jido.AI.Session.Transcript.request_refs(context, entry.refs)
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
