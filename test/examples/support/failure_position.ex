defmodule JidoAI.Examples.FailurePosition.Fault do
  @moduledoc "Observe the real model boundary and fail selected reasoning positions."

  def transform_request(_request, state, _config, context) do
    server = Jido.AgentServer.whereis(Jido.registry_name(context.jido), context.agent_id)
    send(context.observer, {:reasoning_position, state.iteration, state.status, server})

    cond do
      context[:reject_position] == state.iteration -> {:error, :position_rejected}
      context[:reject_repair] == true and state.status == :completed -> {:error, :repair_rejected}
      true -> {:ok, %{}}
    end
  end

  def repair_failure(_, _, _, _), do: {:error, :local_repair_failed}
end
