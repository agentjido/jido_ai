defmodule JidoAI.Examples.StandaloneRuntime.Hold do
  use Jido.Action, name: "hold", schema: Zoi.object(%{})

  def run(_, context) do
    server = Jido.AgentServer.whereis(Jido.registry_name(context.jido), context.agent_id)
    send(context.observer, {:standalone_tool_waiting, self(), server})

    receive do
      :release -> {:ok, %{released: true}}
    end
  end
end

defmodule JidoAI.Examples.StandaloneRuntime.Before do
  def before_tool_call(call, context) do
    send(context.observer, {:standalone_before, call})
    {:ok, %{call | arguments: %{"a" => call.arguments["a"], "b" => 8}}}
  end
end

defmodule JidoAI.Examples.StandaloneRuntime.After do
  def after_tool_call(call, {:ok, value, effects}, context) do
    send(context.observer, {:standalone_after, call, value})
    {:ok, {:ok, %{sum: value.sum * 10}, effects}}
  end
end

defmodule JidoAI.Examples.StandaloneRuntime.Both do
  defdelegate before_tool_call(call, context), to: JidoAI.Examples.StandaloneRuntime.Before
  defdelegate after_tool_call(call, result, context), to: JidoAI.Examples.StandaloneRuntime.After
end

defmodule JidoAI.Examples.StandaloneRuntime.RepairTransform do
  def transform_request(request, state, _config, context) do
    send(context.observer, {:standalone_repair_transform, state.status, request})

    case {state.status, context[:repair_mode]} do
      {:completed, :error} -> {:error, :repair_credentials_unavailable}
      {:completed, :invalid_messages} -> {:ok, %{messages: :invalid}}
      _ -> {:ok, %{llm_opts: [api_key: "native-repair-key"]}}
    end
  end
end
