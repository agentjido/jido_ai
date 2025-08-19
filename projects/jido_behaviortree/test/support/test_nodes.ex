defmodule Jido.BehaviorTree.Test.Nodes do
  @moduledoc """
  Test node implementations for behavior tree testing.
  """

  defmodule SimpleNode do
    @moduledoc "A simple test node that always succeeds"

    use TypedStruct

    typedstruct do
      field(:data, term(), default: nil)
      field(:tick_count, non_neg_integer(), default: 0)
    end

    @behaviour Jido.BehaviorTree.Node

    @impl true
    def tick(node_state, _tick) do
      updated_state = %{node_state | tick_count: node_state.tick_count + 1}
      {:success, updated_state}
    end

    @impl true
    def halt(node_state) do
      %{node_state | tick_count: 0}
    end

    def new(data \\ nil) do
      %__MODULE__{data: data}
    end
  end

  defmodule FailureNode do
    @moduledoc "A test node that always fails"

    use TypedStruct

    typedstruct do
      field(:reason, term(), default: "test failure")
    end

    @behaviour Jido.BehaviorTree.Node

    @impl true
    def tick(node_state, _tick) do
      {:failure, node_state}
    end

    @impl true
    def halt(node_state) do
      node_state
    end

    def new(reason \\ "test failure") do
      %__MODULE__{reason: reason}
    end
  end

  defmodule RunningNode do
    @moduledoc "A test node that stays running until tick count reaches threshold"

    use TypedStruct

    typedstruct do
      field(:threshold, non_neg_integer(), default: 3)
      field(:tick_count, non_neg_integer(), default: 0)
    end

    @behaviour Jido.BehaviorTree.Node

    @impl true
    def tick(node_state, _tick) do
      updated_state = %{node_state | tick_count: node_state.tick_count + 1}

      if updated_state.tick_count >= node_state.threshold do
        {:success, updated_state}
      else
        {:running, updated_state}
      end
    end

    @impl true
    def halt(node_state) do
      %{node_state | tick_count: 0}
    end

    def new(threshold \\ 3) do
      %__MODULE__{threshold: threshold}
    end
  end

  defmodule ErrorNode do
    @moduledoc "A test node that throws an error"

    use TypedStruct

    typedstruct do
      field(:error_message, String.t(), default: "test error")
    end

    @behaviour Jido.BehaviorTree.Node

    @impl true
    def tick(node_state, _tick) do
      {{:error, node_state.error_message}, node_state}
    end

    @impl true
    def halt(node_state) do
      node_state
    end

    def new(error_message \\ "test error") do
      %__MODULE__{error_message: error_message}
    end
  end

  defmodule BlackboardNode do
    @moduledoc "A test node that reads/writes to blackboard"

    use TypedStruct

    typedstruct do
      field(:read_key, atom())
      field(:write_key, atom())
      field(:write_value, term())
    end

    @behaviour Jido.BehaviorTree.Node

    @impl true
    def tick(node_state, tick) do
      # Read from blackboard if read_key is set
      read_value =
        if node_state.read_key do
          Jido.BehaviorTree.Tick.get(tick, node_state.read_key)
        else
          nil
        end

      # Write to blackboard if write_key is set
      _updated_tick =
        if node_state.write_key do
          Jido.BehaviorTree.Tick.put(tick, node_state.write_key, node_state.write_value)
        else
          tick
        end

      # Store read value in node state for verification  
      updated_state = %{node_state | read_key: read_value}

      {:success, updated_state}
    end

    @impl true
    def halt(node_state) do
      node_state
    end

    def new(opts \\ []) do
      %__MODULE__{
        read_key: Keyword.get(opts, :read_key),
        write_key: Keyword.get(opts, :write_key),
        write_value: Keyword.get(opts, :write_value)
      }
    end
  end
end
