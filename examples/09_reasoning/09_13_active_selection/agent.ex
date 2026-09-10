defmodule JidoAI.Examples.ActiveSelection.Observer do
  use Jido.Plugin, agent_server: JidoAI.Examples.ActiveSelection.Observer.AgentServer
end

defmodule JidoAI.Examples.ActiveSelection.Observer.AgentServer do
  use Jido.AgentServer.Plugin

  @impl true
  def admit(_runtime_ref, command, _opts) do
    if command.signal.type == Jido.AI.Session.progress_type() do
      send(command.context.observer, {:selection_commit, command.signal})

      if command.context[:reject_progress],
        do: {:error, :progress_policy_rejected},
        else: {:ok, command}
    else
      {:ok, command}
    end
  end
end

defmodule JidoAI.Examples.ActiveSelection.Agent do
  use Jido.AI.AdaptiveAgent,
    name: "active_method_selection",
    model: :example,
    tools: [JidoAI.Examples.ToT.Work],
    plugins: [JidoAI.Examples.ActiveSelection.Observer],
    method_options: %{tot: %{max_depth: 1, branching_factor: 2}}
end

defmodule JidoAI.Examples.ActiveSelection.Input do
  @behaviour Jido.AI.Control

  @impl true
  def check(_query, context) do
    send(context.observer, {:before_selection, self()})

    receive do
      :continue_selection -> :ok
      :reject_selection -> {:error, :input_rejected}
    end
  end
end
