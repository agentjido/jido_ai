defmodule Jido.HTN.PrimitiveTask do
  @moduledoc """
  Represents a primitive task in the HTN planning system, integrated with the Jido Workflow framework.
  """

  @type action :: Jido.Action.t()
  @type params :: keyword()
  @type context :: map()
  @type scheduling_constraints :: %{
          optional(:earliest_start_time) => non_neg_integer(),
          optional(:latest_end_time) => non_neg_integer()
        }

  @type t :: %__MODULE__{
          name: String.t(),
          preconditions: [(map() -> boolean())],
          task: {action(), params()},
          effects: [(any() -> map())],
          expected_effects: [(map() -> map())],
          cost: non_neg_integer() | nil,
          duration: non_neg_integer() | nil,
          scheduling_constraints: scheduling_constraints() | nil,
          background: boolean()
        }

  defstruct [
    :name,
    :task,
    :cost,
    :duration,
    :scheduling_constraints,
    preconditions: [],
    effects: [],
    expected_effects: [],
    background: false
  ]

  @doc """
  Creates a new primitive task.

  ## Options
  - `:preconditions` - List of functions that take a world state and return a boolean
  - `:effects` - List of functions that take a result and return a map of world state changes
  - `:expected_effects` - List of functions that take a world state and return expected changes
  - `:cost` - Optional cost of executing the task
  - `:duration` - Optional duration of the task in milliseconds
  - `:scheduling_constraints` - Optional map of scheduling constraints (earliest_start_time, latest_end_time)
  - `:background` - Whether this task should execute in the background (default: false)
  """
  @spec new(String.t(), {action(), params()}, keyword()) :: t()
  def new(name, task, opts \\ []) when is_binary(name) do
    %__MODULE__{
      name: name,
      task: task,
      preconditions: Keyword.get(opts, :preconditions, []),
      effects: Keyword.get(opts, :effects, []),
      expected_effects: Keyword.get(opts, :expected_effects, []),
      cost: Keyword.get(opts, :cost),
      duration: Keyword.get(opts, :duration),
      scheduling_constraints: Keyword.get(opts, :scheduling_constraints),
      background: Keyword.get(opts, :background, false)
    }
  end

  @doc """
  Executes the primitive task with the given context.
  If the task is a background task, it will be started but not waited for completion.
  """
  @spec execute(t(), context()) :: {:ok, map()} | {:error, any()}
  def execute(%__MODULE__{task: {_action, _params}, background: true}, _context) do
    # For background tasks, start them but don't wait for completion
    # Return an empty map since we don't have immediate results
    raise "Jido.Workflow.run/3 is not implemented. Please provide an implementation."
    # Task.start(fn -> Workflow.run(action, params, context) end)
    # {:ok, %{}}
  end

  def execute(%__MODULE__{task: {_action, _params}}, _context) do
    raise "Jido.Workflow.run/3 is not implemented. Please provide an implementation."
    # Workflow.run(action, params, context)
  end
end
