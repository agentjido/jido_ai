defmodule Jido.AI.Session.Plugin.AgentServer do
  @moduledoc false
  use Jido.AgentServer.Plugin

  alias Jido.AI.Session.{Plugin, Runtime}

  def child_spec(init), do: Supervisor.child_spec({Runtime, init}, id: Plugin)

  @impl Jido.AgentServer.Plugin
  def await_ready(runtime, _opts), do: GenServer.call(runtime, :ready)

  @impl Jido.AgentServer.Plugin
  def admit(runtime, command, opts) do
    with {:ok, command} <- Plugin.prepare_admission(runtime, command, opts),
         do: Plugin.prepare_command(command)
  end

  @impl Jido.AgentServer.Plugin
  def dispatch(runtime, directive, context, _opts),
    do: Plugin.dispatch_directive(runtime, directive, context)
end
