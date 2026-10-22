defmodule Jido.AI.Orchestration.Plugin.AgentServer do
  @moduledoc false
  @behaviour Jido.Plugin

  alias Jido.AI.Orchestration.{Plugin, Coordinator}

  @impl Jido.Plugin
  def child_spec(init), do: Supervisor.child_spec({Coordinator, init}, id: Plugin)

  @impl Jido.Plugin
  def await_ready(runtime, _opts), do: GenServer.call(runtime, :ready)

  @impl Jido.Plugin
  def admit(runtime, admission, opts), do: Plugin.prepare_admission(runtime, admission, opts)

  @impl Jido.Plugin
  def dispatch(runtime, directive, context, _opts),
    do: Plugin.dispatch_directive(runtime, directive, context)
end
