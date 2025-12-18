defmodule Jido.Runner do
  @moduledoc """
  Behavior for executing planned actions on an Agent.

  Jido provides two built-in runners:

  - `Jido.Runner.Simple` - Executes a single instruction from the agent's queue,
    handling state updates and directives atomically.

  - `Jido.Runner.Chain` - Executes multiple instructions sequentially, with results
    flowing between steps and support for directive-based flow control.
  """

  @type action :: module() | {module(), map()}

  @callback run(agent :: struct(), opts :: keyword()) ::
              {:ok, struct(), list()} | {:error, Jido.Error.t()}
end
