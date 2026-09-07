defmodule Jido.AI.Reasoning.ReAct.Strategy do
  @moduledoc """
  Compatibility tool view for ReAct Agents.

  V3 executes requests through Agent routes, Flow and Session. Use the public
  Agent request functions and `Jido.AI.Session.snapshot/2`. The removed core
  Strategy callbacks (`init`, `cmd`, `snapshot`, `signal_routes`, `action_spec`)
  and worker event commands are not execution entry points in v3.
  """

  @deprecated "Use Jido.AI.list_tools/1"
  defdelegate list_tools(agent), to: Jido.AI
end
