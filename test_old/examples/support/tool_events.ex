defmodule JidoAI.Examples.ToolEvents do
  @moduledoc false

  # These shared tool identities require serial tests. Observe the public
  # executor boundary rather than adding test callbacks to the tools.
  def attach do
    id = {__MODULE__, make_ref()}
    :ok = :telemetry.attach_many(id, [[:jido, :action, :start], [:jido, :flow, :start]], &__MODULE__.handle/4, self())
    ExUnit.Callbacks.on_exit(fn -> :telemetry.detach(id) end)
    :ok
  end

  def attach_action(module) do
    id = {__MODULE__, make_ref()}
    :ok = :telemetry.attach(id, [:jido, :action, :start], &__MODULE__.handle_action/4, {self(), module.name()})
    ExUnit.Callbacks.on_exit(fn -> :telemetry.detach(id) end)
    :ok
  end

  def handle_action(_event, _measurements, %{name: name}, {pid, name}),
    do: send(pid, {:example_action_started, name})

  def handle_action(_event, _measurements, _metadata, _config), do: :ok

  def handle([:jido, :action, :start], _measurements, %{name: "v3_example_multiply"}, pid) do
    send(pid, {:example_tool_started, "multiply"})
  end

  def handle([:jido, :flow, :start], _measurements, %{flow: "v3_example_quote"}, pid) do
    send(pid, {:example_tool_started, "quote"})
  end

  def handle(_event, _measurements, _metadata, _config), do: :ok
end
