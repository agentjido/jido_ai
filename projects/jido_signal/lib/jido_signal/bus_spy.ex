defmodule Jido.Signal.BusSpy do
  @moduledoc """
  A test utility for observing signals crossing process boundaries via telemetry events.

  The BusSpy allows test processes to capture the exact signals that travel across
  process boundaries through the Signal Bus without interfering with normal signal
  delivery. It integrates cleanly with existing cross-process test infrastructure.

  ## Usage

  ```elixir
  test "cross-process signal observation" do
    # Start the spy to capture bus events
    spy = BusSpy.start_spy()
    
    # Set up your cross-process test scenario
    %{producer: producer, consumer: consumer} = setup_cross_process_agents()
    
    # Send a signal that will cross process boundaries
    send_signal_sync(producer, :root, %{test_data: "cross-process"})
    
    # Wait for completion
    wait_for_cross_process_completion([consumer])
    
    # Verify the signal was observed crossing the bus
    dispatched_signals = BusSpy.get_dispatched_signals(spy)
    assert length(dispatched_signals) == 1
    
    [signal_event] = dispatched_signals
    assert signal_event.signal.type == "child.event"
    assert signal_event.signal.data.test_data == "cross-process"
    
    # Verify trace context was preserved
    assert signal_event.signal.trace_context != nil
    
    BusSpy.stop_spy(spy)
  end
  ```

  ## Events Captured

  The spy captures these telemetry events:
  - `[:jido, :signal, :bus, :before_dispatch]` - Before signal dispatch
  - `[:jido, :signal, :bus, :after_dispatch]` - After successful dispatch  
  - `[:jido, :signal, :bus, :dispatch_skipped]` - When middleware skips dispatch
  - `[:jido, :signal, :bus, :dispatch_error]` - When dispatch fails

  Each event includes full signal and subscription metadata for test verification.
  """

  use GenServer

  @type spy_ref :: pid()
  @type signal_event :: %{
          event: atom(),
          timestamp: integer(),
          bus_name: atom(),
          signal_id: String.t(),
          signal_type: String.t(),
          subscription_id: String.t(),
          subscription_path: String.t(),
          signal: Jido.Signal.t(),
          subscription: map(),
          dispatch_result: term() | nil,
          error: term() | nil,
          reason: atom() | nil
        }

  @events [
    [:jido, :signal, :bus, :before_dispatch],
    [:jido, :signal, :bus, :after_dispatch],
    [:jido, :signal, :bus, :dispatch_skipped],
    [:jido, :signal, :bus, :dispatch_error]
  ]

  @doc """
  Starts a new bus spy process to collect telemetry events.

  Returns a spy reference that can be used to query captured events.
  """
  @spec start_spy() :: spy_ref()
  def start_spy do
    {:ok, pid} = GenServer.start_link(__MODULE__, [])
    pid
  end

  @doc """
  Stops a bus spy process and cleans up telemetry handlers.
  """
  @spec stop_spy(spy_ref()) :: :ok
  def stop_spy(spy_ref) do
    GenServer.stop(spy_ref)
  end

  @doc """
  Gets all signals that have been dispatched through the bus since the spy started.

  Returns a list of signal events in chronological order.
  """
  @spec get_dispatched_signals(spy_ref()) :: [signal_event()]
  def get_dispatched_signals(spy_ref) do
    GenServer.call(spy_ref, :get_dispatched_signals)
  end

  @doc """
  Gets signals that match a specific signal type pattern.

  ## Examples

      # Get all "user.*" events
      user_events = BusSpy.get_signals_by_type(spy, "user.*")
      
      # Get exact matches
      child_events = BusSpy.get_signals_by_type(spy, "child.event")
  """
  @spec get_signals_by_type(spy_ref(), String.t()) :: [signal_event()]
  def get_signals_by_type(spy_ref, signal_type_pattern) do
    GenServer.call(spy_ref, {:get_signals_by_type, signal_type_pattern})
  end

  @doc """
  Gets the most recent signal event for a specific bus.
  """
  @spec get_latest_signal(spy_ref(), atom()) :: signal_event() | nil
  def get_latest_signal(spy_ref, bus_name) do
    GenServer.call(spy_ref, {:get_latest_signal, bus_name})
  end

  @doc """
  Waits for a signal matching the given type pattern to be dispatched.

  Returns the matching signal event or times out.
  """
  @spec wait_for_signal(spy_ref(), String.t(), non_neg_integer()) ::
          {:ok, signal_event()} | :timeout
  def wait_for_signal(spy_ref, signal_type_pattern, timeout \\ 5000) do
    GenServer.call(spy_ref, {:wait_for_signal, signal_type_pattern, timeout}, timeout + 1000)
  end

  @doc """
  Clears all captured events from the spy.
  """
  @spec clear_events(spy_ref()) :: :ok
  def clear_events(spy_ref) do
    GenServer.call(spy_ref, :clear_events)
  end

  # GenServer Implementation

  def init(_opts) do
    # Attach telemetry handlers for all bus events
    for event <- @events do
      :telemetry.attach(
        {__MODULE__, self(), event},
        event,
        &handle_telemetry_event/4,
        %{spy_pid: self()}
      )
    end

    {:ok, %{events: [], waiters: []}}
  end

  def handle_call(:get_dispatched_signals, _from, state) do
    # Return events in chronological order (oldest first)
    events = Enum.reverse(state.events)
    {:reply, events, state}
  end

  def handle_call({:get_signals_by_type, pattern}, _from, state) do
    matching_events =
      state.events
      |> Enum.reverse()
      |> Enum.filter(fn event ->
        match_signal_type?(event.signal_type, pattern)
      end)

    {:reply, matching_events, state}
  end

  def handle_call({:get_latest_signal, bus_name}, _from, state) do
    latest_event =
      Enum.find(state.events, fn event ->
        event.bus_name == bus_name
      end)

    {:reply, latest_event, state}
  end

  def handle_call({:wait_for_signal, pattern, timeout}, from, state) do
    # Check if we already have a matching signal
    case Enum.find(Enum.reverse(state.events), &match_signal_type?(&1.signal_type, pattern)) do
      nil ->
        # Add to waiters list and set timeout
        ref = Process.monitor(elem(from, 0))
        waiter = %{from: from, pattern: pattern, ref: ref}
        Process.send_after(self(), {:wait_timeout, ref}, timeout)
        {:noreply, %{state | waiters: [waiter | state.waiters]}}

      event ->
        {:reply, {:ok, event}, state}
    end
  end

  def handle_call(:clear_events, _from, state) do
    {:reply, :ok, %{state | events: []}}
  end

  def handle_info({:telemetry_event, event_name, measurements, metadata}, state) do
    # Convert telemetry event to our signal event format
    signal_event = %{
      event: List.last(event_name),
      timestamp: Map.get(measurements, :timestamp, System.monotonic_time(:microsecond)),
      bus_name: Map.get(metadata, :bus_name),
      signal_id: Map.get(metadata, :signal_id),
      signal_type: Map.get(metadata, :signal_type),
      subscription_id: Map.get(metadata, :subscription_id),
      subscription_path: Map.get(metadata, :subscription_path),
      signal: Map.get(metadata, :signal),
      subscription: Map.get(metadata, :subscription),
      dispatch_result: Map.get(metadata, :dispatch_result),
      error: Map.get(metadata, :error),
      reason: Map.get(metadata, :reason)
    }

    # Add to events (newest first for efficient prepending)
    new_events = [signal_event | state.events]

    # Check if any waiters are satisfied
    {satisfied_waiters, remaining_waiters} =
      Enum.split_with(state.waiters, fn waiter ->
        match_signal_type?(signal_event.signal_type, waiter.pattern)
      end)

    # Reply to satisfied waiters
    for waiter <- satisfied_waiters do
      GenServer.reply(waiter.from, {:ok, signal_event})
      Process.demonitor(waiter.ref, [:flush])
    end

    {:noreply, %{state | events: new_events, waiters: remaining_waiters}}
  end

  def handle_info({:wait_timeout, ref}, state) do
    # Find and remove the waiter, reply with timeout
    case Enum.find(state.waiters, &(&1.ref == ref)) do
      nil ->
        {:noreply, state}

      waiter ->
        GenServer.reply(waiter.from, :timeout)
        Process.demonitor(ref, [:flush])
        remaining_waiters = Enum.reject(state.waiters, &(&1.ref == ref))
        {:noreply, %{state | waiters: remaining_waiters}}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    # Remove any waiters for the dead process
    remaining_waiters = Enum.reject(state.waiters, &(&1.ref == ref))
    {:noreply, %{state | waiters: remaining_waiters}}
  end

  def terminate(_reason, _state) do
    # Detach all telemetry handlers
    for event <- @events do
      :telemetry.detach({__MODULE__, self(), event})
    end

    :ok
  end

  # Telemetry event handler - forwards events to the spy process
  def handle_telemetry_event(event_name, measurements, metadata, %{spy_pid: spy_pid}) do
    send(spy_pid, {:telemetry_event, event_name, measurements, metadata})
  end

  # Simple glob-style pattern matching for signal types
  defp match_signal_type?(signal_type, pattern) do
    cond do
      pattern == "*" ->
        true

      pattern == signal_type ->
        true

      String.ends_with?(pattern, "*") ->
        prefix = String.slice(pattern, 0..-2//1)
        String.starts_with?(signal_type, prefix)

      String.starts_with?(pattern, "*") ->
        suffix = String.slice(pattern, 1..-1//1)
        String.ends_with?(signal_type, suffix)

      String.contains?(pattern, "*") ->
        # More complex glob matching could be implemented here
        pattern
        |> String.split("*", parts: 2)
        |> case do
          [prefix, suffix] ->
            String.starts_with?(signal_type, prefix) and String.ends_with?(signal_type, suffix)

          _ ->
            false
        end

      true ->
        false
    end
  end
end
