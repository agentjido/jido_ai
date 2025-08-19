defmodule Jido.BehaviorTree.Node do
  @moduledoc """
  Defines the behavior for all behavior tree nodes.

  Every node in a behavior tree must implement this behavior to define
  how it responds to ticks and how it can be halted when necessary.

  ## Node Types

  There are three main categories of nodes:

  1. **Composite Nodes** - Control the execution of multiple child nodes
     - Sequence: Execute children in order until one fails
     - Selector: Execute children in order until one succeeds
     - Parallel: Execute children concurrently

  2. **Decorator Nodes** - Modify the behavior of a single child node
     - Inverter: Invert the child's success/failure status
     - Repeat: Repeat the child a specified number of times
     - Timeout: Limit the child's execution time

  3. **Leaf Nodes** - Perform actual work or conditions
     - Action: Execute a Jido action
     - Wait: Pause execution for a duration
     - Condition: Check a boolean condition

  ## Implementation

  When implementing a node, you define a struct to hold the node's state
  and implement the two required callbacks:

      defmodule MyNode do
        use TypedStruct

        typedstruct do
          field(:my_data, term())
          # other fields...
        end

        @behaviour Jido.BehaviorTree.Node

        @impl true
        def tick(node_state, tick) do
          # Your tick logic here
          {:success, updated_node_state}
        end

        @impl true
        def halt(node_state) do
          # Your halt logic here
          updated_node_state
        end
      end

  ## Telemetry

  Nodes should emit telemetry events during execution to enable
  monitoring and debugging:

      :telemetry.execute(
        [:jido_behaviortree, :node, :tick],
        %{duration: duration},
        %{node: __MODULE__, status: status}
      )
  """

  alias Jido.BehaviorTree.{Status, Tick}

  @typedoc "Any struct that represents a behavior tree node"
  @type t :: struct()

  @doc """
  Executes a single tick of the node.

  This callback is called when the behavior tree is executed and this node
  is reached. The node should perform its logic and return a status along
  with any updated state.

  ## Parameters

  - `node_state` - The current state of this node
  - `tick` - The current tick context containing blackboard and timing info

  ## Returns

  A tuple containing:
  - The status of the node execution (`:success`, `:failure`, `:running`, or `{:error, reason}`)
  - The updated node state (which may be unchanged)

  ## Examples

      def tick(node_state, tick) do
        case perform_work(node_state, tick) do
          {:ok, result} ->
            {:success, %{node_state | result: result}}
          {:error, reason} ->
            {{:error, reason}, node_state}
        end
      end

  """
  @callback tick(node_state :: t(), tick :: Tick.t()) :: {Status.t(), t()}

  @doc """
  Halts the execution of the node.

  This callback is called when the node needs to stop execution, typically
  when a parent node has completed or the entire tree is being stopped.

  The node should clean up any resources, cancel any ongoing operations,
  and return to a clean state.

  ## Parameters

  - `node_state` - The current state of this node

  ## Returns

  The updated node state after halting

  ## Examples

      def halt(node_state) do
        # Cancel any timers, close connections, etc.
        cancel_timer(node_state.timer)
        %{node_state | timer: nil, status: :halted}
      end

  """
  @callback halt(node_state :: t()) :: t()

  @doc """
  Executes a tick on the given node with telemetry.

  This function wraps the node's tick callback with telemetry events
  and error handling.

  ## Examples

      {status, updated_node} = Jido.BehaviorTree.Node.execute_tick(node, tick)

  """
  @spec execute_tick(t(), Tick.t()) :: {Status.t(), t()}
  def execute_tick(node_state, tick) do
    node_module = node_state.__struct__
    start_time = System.monotonic_time()

    metadata = %{
      node: node_module,
      sequence: tick.sequence
    }

    :telemetry.execute([:jido_behaviortree, :node, :tick, :start], %{}, metadata)

    try do
      {status, updated_node} = node_module.tick(node_state, tick)

      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:jido_behaviortree, :node, :tick, :stop],
        %{duration: duration},
        Map.put(metadata, :status, status)
      )

      {status, updated_node}
    rescue
      error ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:jido_behaviortree, :node, :tick, :exception],
          %{duration: duration},
          Map.merge(metadata, %{error: error, stacktrace: __STACKTRACE__})
        )

        {{:error, error}, node_state}
    end
  end

  @doc """
  Halts the given node with telemetry.

  This function wraps the node's halt callback with telemetry events
  and error handling.

  ## Examples

      updated_node = Jido.BehaviorTree.Node.execute_halt(node)

  """
  @spec execute_halt(t()) :: t()
  def execute_halt(node_state) do
    node_module = node_state.__struct__
    start_time = System.monotonic_time()

    metadata = %{node: node_module}

    :telemetry.execute([:jido_behaviortree, :node, :halt, :start], %{}, metadata)

    try do
      updated_node = node_module.halt(node_state)

      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:jido_behaviortree, :node, :halt, :stop],
        %{duration: duration},
        metadata
      )

      updated_node
    rescue
      error ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:jido_behaviortree, :node, :halt, :exception],
          %{duration: duration},
          Map.merge(metadata, %{error: error, stacktrace: __STACKTRACE__})
        )

        # Return original state if halt failed
        node_state
    end
  end

  @doc """
  Checks if a value implements the Node behavior.

  ## Examples

      iex> Jido.BehaviorTree.Node.node?(%Jido.BehaviorTree.Nodes.Action{})
      true

      iex> Jido.BehaviorTree.Node.node?("not a node")
      false

  """
  @spec node?(term()) :: boolean()
  def node?(value) do
    is_struct(value) and function_exported?(value.__struct__, :tick, 2)
  end
end
