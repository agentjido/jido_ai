defmodule Jido.AI do
  @moduledoc """
  A graph-first AI Agent experiment for Jido.

  `use Jido.AI.Agent` defines a normal Jido Agent with one required root
  reasoning Flow:

      defmodule MyAgent do
        use Jido.AI.Agent, name: "my_agent"

        ai do
          reasoning Jido.AI.Strategy.ReAct
        end
      end

  The Agent owns the runtime boundary. The reasoning Flow is the direct target
  of its request route. Jido AI does not add a hidden orchestration pipeline.

  Flow components define the control behavior. `Jido.AI.SimpleAgent` expands
  guarded model and tool Flows through terminal Dispatch components. A Flow
  Parallel component executes validated tool calls as separate Action nodes
  and joins their ordered results.

  The first Agent is `Jido.AI.SimpleAgent`. Send it a request Signal:

      agent = Jido.AI.SimpleAgent.instantiate!(id: "example")
      signal = Jido.AI.SimpleAgent.request_signal!(%{input: "Say hello."})
      Jido.AI.SimpleAgent.cmd(agent, signal)
  """
end
