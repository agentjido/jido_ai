defmodule Jido.AI.Orchestration.Plugin.AgentServer do
  @moduledoc false
  use Jido.AgentServer.Plugin

  alias Jido.AI.Orchestration.{Plugin, Coordinator}

  def child_spec(init), do: Supervisor.child_spec({Coordinator, init}, id: Plugin)

  @impl Jido.AgentServer.Plugin
  def await_ready(runtime, _opts), do: GenServer.call(runtime, :ready)

  @impl Jido.AgentServer.Plugin
  def admit(runtime, admission, opts), do: Plugin.prepare_admission(runtime, admission, opts)

  @impl Jido.AgentServer.Plugin
  def dispatch(runtime, directive, context, _opts),
    do: Plugin.dispatch_directive(runtime, directive, context)
end
