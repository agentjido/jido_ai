defmodule Jido.BehaviorTree.Agent do
  @moduledoc """
  A simple behavior tree executor using a GenServer.

  This agent provides a stateful execution environment for behavior trees,
  maintaining the tree state and blackboard between ticks. It supports
  both manual and automatic execution modes.

  ## Features

  - Execute behavior trees with automatic state management
  - Maintain shared blackboard between executions
  - Support for manual or automatic tree progression
  - Built-in telemetry and logging

  ## Example Usage

      # Create a simple tree
      tree = Jido.BehaviorTree.Tree.new(simple_node)

      # Start the agent
      {:ok, agent} = Jido.BehaviorTree.Agent.start_link(
        tree: tree,
        blackboard: %{status: :ready},
        mode: :manual
      )

      # Tick the tree manually
      status = Jido.BehaviorTree.Agent.tick(agent)

      # Get current blackboard
      bb = Jido.BehaviorTree.Agent.blackboard(agent)
  """

  use GenServer
  require Logger

  alias Jido.BehaviorTree.{Tree, Tick, Blackboard, Status}

  @typedoc "Agent execution mode"
  @type mode :: :manual | :auto

  @typedoc "Agent state"
  @type state :: %{
          tree: Tree.t(),
          blackboard: Blackboard.t(),
          mode: mode(),
          interval: non_neg_integer() | nil,
          timer_ref: reference() | nil,
          tick_count: non_neg_integer()
        }

  @default_interval 1000

  ## Public API

  @doc """
  Starts a behavior tree agent.

  ## Options

  - `:tree` - The behavior tree to execute (required)
  - `:blackboard` - Initial blackboard data (default: empty blackboard)
  - `:mode` - Execution mode, either `:manual` or `:auto` (default: `:manual`)
  - `:interval` - Tick interval in milliseconds for auto mode (default: 1000)

  ## Examples

      {:ok, agent} = Jido.BehaviorTree.Agent.start_link(
        tree: tree,
        blackboard: %{user_id: 123},
        mode: :auto,
        interval: 2000
      )

  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    tree = Keyword.fetch!(opts, :tree)
    blackboard_data = Keyword.get(opts, :blackboard, %{})
    mode = Keyword.get(opts, :mode, :manual)
    interval = Keyword.get(opts, :interval, @default_interval)

    initial_state = %{
      tree: tree,
      blackboard: Blackboard.new(blackboard_data),
      mode: mode,
      interval: interval,
      timer_ref: nil,
      tick_count: 0
    }

    GenServer.start_link(__MODULE__, initial_state, opts)
  end

  @doc """
  Executes a single tick of the behavior tree.

  Returns the status of the tree execution.

  ## Examples

      status = Jido.BehaviorTree.Agent.tick(agent)

  """
  @spec tick(pid()) :: Status.t()
  def tick(pid) do
    GenServer.call(pid, :tick)
  end

  @doc """
  Gets the current blackboard.

  ## Examples

      bb = Jido.BehaviorTree.Agent.blackboard(agent)

  """
  @spec blackboard(pid()) :: Blackboard.t()
  def blackboard(pid) do
    GenServer.call(pid, :blackboard)
  end

  @doc """
  Puts a value in the blackboard.

  ## Examples

      :ok = Jido.BehaviorTree.Agent.put(agent, :key, "value")

  """
  @spec put(pid(), term(), term()) :: :ok
  def put(pid, key, value) do
    GenServer.call(pid, {:put, key, value})
  end

  @doc """
  Gets a value from the blackboard.

  ## Examples

      value = Jido.BehaviorTree.Agent.get(agent, :key, "default")

  """
  @spec get(pid(), term(), term()) :: term()
  def get(pid, key, default \\ nil) do
    GenServer.call(pid, {:get, key, default})
  end

  @doc """
  Replaces the root node of the tree.

  ## Examples

      :ok = Jido.BehaviorTree.Agent.replace_root(agent, new_root)

  """
  @spec replace_root(pid(), Jido.BehaviorTree.Node.t()) :: :ok
  def replace_root(pid, new_root) do
    GenServer.call(pid, {:replace_root, new_root})
  end

  @doc """
  Halts the agent and cleans up the tree.

  ## Examples

      :ok = Jido.BehaviorTree.Agent.halt(agent)

  """
  @spec halt(pid()) :: :ok
  def halt(pid) do
    GenServer.call(pid, :halt)
  end

  @doc """
  Gets the current execution mode.

  ## Examples

      mode = Jido.BehaviorTree.Agent.mode(agent)

  """
  @spec mode(pid()) :: mode()
  def mode(pid) do
    GenServer.call(pid, :mode)
  end

  @doc """
  Sets the execution mode.

  When changing to `:auto` mode, automatic ticking will start.
  When changing to `:manual` mode, automatic ticking will stop.

  ## Examples

      :ok = Jido.BehaviorTree.Agent.set_mode(agent, :auto)

  """
  @spec set_mode(pid(), mode()) :: :ok
  def set_mode(pid, new_mode) do
    GenServer.call(pid, {:set_mode, new_mode})
  end

  ## GenServer Callbacks

  @impl true
  def init(state) do
    if state.mode == :auto do
      {:ok, schedule_tick(state)}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_call(:tick, _from, state) do
    {status, new_state} = do_tick(state)
    {:reply, status, new_state}
  end

  def handle_call(:blackboard, _from, state) do
    {:reply, state.blackboard, state}
  end

  def handle_call({:put, key, value}, _from, state) do
    updated_bb = Blackboard.put(state.blackboard, key, value)
    new_state = %{state | blackboard: updated_bb}
    {:reply, :ok, new_state}
  end

  def handle_call({:get, key, default}, _from, state) do
    value = Blackboard.get(state.blackboard, key, default)
    {:reply, value, state}
  end

  def handle_call({:replace_root, new_root}, _from, state) do
    updated_tree = Tree.replace_root(state.tree, new_root)
    new_state = %{state | tree: updated_tree}
    {:reply, :ok, new_state}
  end

  def handle_call(:halt, _from, state) do
    halted_tree = Tree.halt(state.tree)
    new_state = %{state | tree: halted_tree}
    {:reply, :ok, cancel_timer(new_state)}
  end

  def handle_call(:mode, _from, state) do
    {:reply, state.mode, state}
  end

  def handle_call({:set_mode, new_mode}, _from, state) do
    new_state =
      case {state.mode, new_mode} do
        {:manual, :auto} ->
          %{state | mode: new_mode} |> schedule_tick()

        {:auto, :manual} ->
          %{state | mode: new_mode} |> cancel_timer()

        _ ->
          %{state | mode: new_mode}
      end

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:tick, state) do
    {_status, new_state} = do_tick(state)

    # Schedule next tick if still in auto mode
    final_state =
      if new_state.mode == :auto do
        schedule_tick(new_state)
      else
        new_state
      end

    {:noreply, final_state}
  end

  @impl true
  def terminate(_reason, state) do
    # Ensure tree is properly halted
    Tree.halt(state.tree)
    cancel_timer(state)
    :ok
  end

  ## Private Functions

  defp do_tick(state) do
    start_time = System.monotonic_time()

    # Create tick context
    tick = Tick.new(state.blackboard)

    # Emit telemetry
    :telemetry.execute(
      [:jido_behaviortree, :agent, :tick, :start],
      %{},
      %{tick_count: state.tick_count}
    )

    # Execute the tree
    {status, updated_tree} = Tree.tick(state.tree, tick)

    # Extract updated blackboard from tick
    updated_blackboard = tick.blackboard

    duration = System.monotonic_time() - start_time

    # Emit completion telemetry
    :telemetry.execute(
      [:jido_behaviortree, :agent, :tick, :stop],
      %{duration: duration},
      %{tick_count: state.tick_count, status: status}
    )

    new_state = %{
      state
      | tree: updated_tree,
        blackboard: updated_blackboard,
        tick_count: state.tick_count + 1
    }

    {status, new_state}
  end

  defp schedule_tick(state) do
    timer_ref = Process.send_after(self(), :tick, state.interval)
    %{state | timer_ref: timer_ref}
  end

  defp cancel_timer(state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    %{state | timer_ref: nil}
  end
end
