defmodule Jido.AI.Orchestration.ExecutionBridge do
  @moduledoc false
  alias Jido.AI.Orchestration.ExecutionBinding

  # Progress replies describe observation only. They are not commit receipts.
  def report(context, fact) do
    with :ok <- validate_fact(fact),
         {:ok, binding} <- ExecutionBinding.fetch(context) do
      case binding do
        nil -> ownerless(context, fact)
        binding -> call(binding, {:report, fact})
      end
    end
  end

  def snapshot(context) do
    with {:ok, binding} <- ExecutionBinding.fetch(context) do
      if binding, do: call(binding, :snapshot), else: {:ok, %{seq: 0}}
    end
  end

  # Views expose data, not the Coordinator or AgentServer protocol.
  def request(context) do
    with {:ok, binding} <- ExecutionBinding.fetch(context) do
      {:ok, if(binding, do: Map.take(binding, [:request_id, :run_id, :source, :extra_refs]))}
    end
  end

  def checkpoint(context) do
    with {:ok, binding} <- ExecutionBinding.fetch(context), do: {:ok, if(binding, do: binding.checkpoint)}
  end

  # The existing public transformer Config includes this caller-facing queue.
  # Runtime steps use input/2, not this resource view.
  def pending_input_server(context) do
    with {:ok, binding} <- ExecutionBinding.fetch(context), do: {:ok, if(binding, do: binding.input_queue)}
  end

  def input(context, operation) when operation in [:drain, :seal, :seal_if_empty] do
    with {:ok, binding} <- ExecutionBinding.fetch(context) do
      if binding, do: call(binding, {:input, operation}), else: empty_input(operation)
    end
  end

  defp empty_input(:drain), do: {:ok, []}
  defp empty_input(:seal), do: :ok
  defp empty_input(:seal_if_empty), do: :sealed

  def pause(context, phase, saved) do
    with {:ok, %ExecutionBinding{} = binding} <- ExecutionBinding.fetch(context) do
      call(binding, {:checkpoint, phase, saved}, :infinity)
    else
      {:ok, nil} -> {:error, :checkpoint_owner_required}
      error -> error
    end
  end

  # This is called by the standalone stream consumer, not by the Flow worker.
  # Coordinator checks both the event ID and the sink process identity.
  def acknowledge(server, request_id, event_id) do
    case Jido.AgentServer.children(server)[{:plugin, Jido.AI.Orchestration.Plugin}] do
      %{pid: owner} -> GenServer.call(owner, {:checkpoint_ack, request_id, event_id})
      _ -> {:error, :execution_owner_unavailable}
    end
  catch
    :exit, _ -> {:error, :execution_owner_unavailable}
  end

  def commit_entries(context, entries) do
    with {:ok, binding} <- ExecutionBinding.fetch(context) do
      cond do
        is_nil(binding) ->
          {:ok, :unmanaged}

        not binding.retain_history? ->
          with {:ok, _} <- call(binding, :snapshot), do: {:ok, :not_retained}

        true ->
          with {:ok, batch_id} <- call(binding, {:stage_entries, entries}) do
            signal =
              Jido.Signal.new!(
                Jido.AI.Orchestration.history_type(),
                %{request_id: binding.request_id, batch_id: batch_id},
                source: "/jido/ai/request"
              )

            commit(binding, signal, %{}, System.monotonic_time(:millisecond) + 5_000, :entries)
          end
      end
    end
  end

  def commit_selection(context, selection, deadline) do
    with {:ok, binding} <- ExecutionBinding.fetch(context) do
      cond do
        is_nil(binding) ->
          {:ok, :unmanaged}

        is_nil(selection) ->
          {:ok, :not_required}

        true ->
          with {:ok, ticket} <- call(binding, {:stage_selection, selection}) do
            signal =
              Jido.Signal.new!(
                Jido.AI.Orchestration.progress_type(),
                %{request_id: binding.request_id, run_id: binding.run_id, ticket: ticket},
                source: "/jido/ai/request"
              )

            commit(binding, signal, Jido.AI.Orchestration.caller_context(context), deadline, :selection)
          end
      end
    end
  end

  # Stage with the owner, then call core from the worker. Calling core inside
  # a Coordinator callback would block the Plugin admission/Directive calls.
  # Only known pre-execution refusals can retry the same staged batch.
  defp commit(binding, signal, context, deadline, kind) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0 do
      case Jido.AgentServer.call(binding.agent_server, signal, context: context, timeout: remaining) do
        {:ok, _} ->
          {:ok, :committed}

        {:error, reason}
        when reason in [:reentrant_turn, :reentrant_admission, :reentrant_directive] or
               (reason == :busy and kind == :selection) ->
          Process.sleep(min(10, remaining))
          commit(binding, signal, context, deadline, kind)

        {:error, reason} ->
          commit_error(reason)
      end
    else
      {:error, {:execution_commit_rejected, :deadline_exhausted}}
    end
  catch
    :exit, reason -> {:error, {:execution_commit_unknown, Jido.AI.Error.for_storage(reason)}}
  end

  defp commit_error({:persistence_failed, reason} = error)
       when reason == :indeterminate or (is_tuple(reason) and elem(reason, 0) == :indeterminate),
       do: {:error, {:execution_commit_unknown, error}}

  defp commit_error(
         {:persistence_failed, %Jido.Error.ExecutionError{details: %{operation: :compare_and_swap}}} = error
       ),
       do: {:error, {:execution_commit_unknown, error}}

  defp commit_error(error), do: {:error, {:execution_commit_rejected, error}}

  defp validate_fact({:event, kind, data}) when is_atom(kind) and is_map(data), do: :ok
  defp validate_fact({:activity, :progress}), do: :ok
  defp validate_fact({:activity, {:tool_finished, id}}) when is_binary(id), do: :ok
  defp validate_fact({:reasoning_iteration, n}) when is_integer(n) and n > 0, do: :ok
  defp validate_fact({:reasoning, data}) when is_map(data) or is_nil(data), do: :ok
  defp validate_fact({:usage, usage}) when is_map(usage) or is_nil(usage), do: :ok
  defp validate_fact({:failure_type, type}) when is_atom(type), do: :ok
  defp validate_fact({:tool_signature, signature}) when is_binary(signature), do: :ok
  defp validate_fact({:output, kind, meta, data}) when is_atom(kind) and is_map(meta) and is_map(data), do: :ok
  defp validate_fact(_), do: {:error, :invalid_execution_report}

  defp ownerless(context, {:output, kind, _meta, data}) do
    event = Map.merge(context.jido_ai_output_event, %{kind: kind, data: data})
    Jido.AI.Observe.Telemetry.emit(event, event.observability, context[:jido_ai_agent_id], event.model)
    {:ok, :unmanaged}
  end

  defp ownerless(_, _), do: {:ok, :unmanaged}

  defp call(binding, command, timeout \\ 5_000) do
    GenServer.call(binding.coordinator, {:execution, binding.request_id, binding.run_id, command}, timeout)
  catch
    :exit, {:timeout, _} -> {:error, :execution_owner_timeout}
    :exit, _ -> {:error, :execution_owner_unavailable}
  end
end
