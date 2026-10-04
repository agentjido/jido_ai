defmodule Jido.AI.Orchestration.Plugin.AgentServer do
  @moduledoc false
  alias Jido.AI.Orchestration.{Plugin, Coordinator}

  def child_spec(init), do: Supervisor.child_spec({Coordinator, init}, id: Plugin)

  def await_ready(runtime, _opts), do: GenServer.call(runtime, :ready)

  def admit(runtime, admission, opts), do: Plugin.prepare_admission(runtime, admission, opts)

  def dispatch(runtime, directive, context, _opts),
    do: Plugin.dispatch_directive(runtime, directive, context)
end
