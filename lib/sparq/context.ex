defmodule Sparq.Context do
  @moduledoc """
  Manages program execution context including call stack, debugging state,
  and execution metrics. Replaces the former Metadata module with a more
  focused and robust implementation.
  """

  alias Sparq.Error

  defstruct [
    # Identity & Parent Relationship
    # Reference for global identity
    ref: nil,
    # PID of parent process
    parent_pid: nil,

    # Execution State
    # :ready | :running | :halted | :error
    status: :ready,
    # Time execution started
    start_time: nil,
    # Time execution ended
    end_time: nil,
    # Total execution time
    execution_time_ns: nil,

    # Call Stack Management
    # Queue of stack frames
    call_stack: :queue.new(),
    # Current active stack frame
    current_frame: nil,

    # Debug & Instrumentation
    # Global debug flag
    debug_mode: false,
    # Step-by-step execution flag
    step_mode: false,
    # Set of {module, line} breakpoints
    breakpoints: MapSet.new(),
    # PIDs subscribed to debug events
    subscribers: MapSet.new(),
    # Bitfield for controlling event types
    event_mask: 0xFFFFFFFF,
    # Recent debug events
    event_history: :queue.new(),

    # Source Location
    # Current source file
    file: nil,
    # Current line number
    line: nil,
    # Current module being executed
    module: nil,

    # Execution Metrics
    # Number of execution steps
    step_count: 0,
    # Maximum allowed stack depth
    max_stack_depth: 100,

    # Registry of module frames
    # <--- Added
    modules: %{},

    # Version & Config
    # Context version
    version: "1.0.0"
  ]

  @type status :: :ready | :running | :halted | :error
  @type t :: %__MODULE__{}

  @doc """
  Creates a new Context with optional configuration.
  """
  def new(opts \\ []) do
    context = struct(__MODULE__, opts)
    %{context | ref: make_ref()}
  end

  @doc """
  Returns the execution trace from the context's event history.
  """
  def get_trace(%__MODULE__{} = context) do
    :queue.to_list(context.event_history)
  end

  @doc """
  Returns the execution time in microseconds.
  """
  def get_timing(%__MODULE__{execution_time_ns: nil}), do: nil

  def get_timing(%__MODULE__{execution_time_ns: time_ns}) do
    time_ns / 1000.0
  end

  @doc """
  Pushes a new stack frame onto the call stack.
  """
  def push_frame(context, frame_type, opts \\ []) do
    parent_ref = if context.current_frame, do: context.current_frame.ref

    frame =
      Sparq.Frame.new([type: frame_type, parent_ref: parent_ref] ++ normalize_variables(opts))

    if :queue.len(context.call_stack) >= context.max_stack_depth do
      %{
        context
        | status: :error,
          current_frame: frame,
          event_history:
            :queue.in(
              {:error,
               Error.new(:stack_overflow, "Maximum stack depth exceeded",
                 context_ref: context.ref,
                 frame_ref: frame.ref,
                 line: context.line,
                 file: context.file
               )},
              context.event_history
            )
      }
    else
      %{context | call_stack: :queue.in(frame, context.call_stack), current_frame: frame}
    end
  end

  defp normalize_variables(opts) do
    case Keyword.get(opts, :variables) do
      nil ->
        opts

      vars when is_map(vars) ->
        normalized = Map.new(vars, fn {k, v} -> {to_string(k), v} end)
        Keyword.put(opts, :variables, normalized)
    end
  end

  @doc """
  Pops the current frame from the call stack.
  """
  def pop_frame(%{call_stack: call_stack} = context) do
    case :queue.out_r(call_stack) do
      {{:value, _frame}, new_queue} ->
        case :queue.peek_r(new_queue) do
          {:value, new_current} ->
            %{context | call_stack: new_queue, current_frame: new_current}

          :empty ->
            %{context | call_stack: new_queue, current_frame: nil}
        end

      {:empty, _} ->
        raise Error.new(:runtime_error, "Stack underflow",
                context_ref: context.ref,
                line: context.line,
                file: context.file
              )
    end
  end

  @doc """
  Starts execution timing and updates status.
  """
  def start_execution(context) do
    %{context | status: :running, start_time: :erlang.monotonic_time(:nanosecond)}
  end

  @doc """
  Halts execution and calculates final timing.
  """
  def halt_execution(%{start_time: start_time} = context) when not is_nil(start_time) do
    end_time = :erlang.monotonic_time(:nanosecond)
    %{context | status: :halted, end_time: end_time, execution_time_ns: end_time - start_time}
  end

  @doc """
  Adds an error to the context and updates status.
  """
  def add_error(context, error) do
    %{context | status: :error, event_history: :queue.in({:error, error}, context.event_history)}
  end

  @doc """
  Retrieves the current stack trace.
  """
  def get_stack_trace(context) do
    context.call_stack
    |> :queue.to_list()
    |> Enum.map(&format_frame_trace/1)
  end

  @doc """
  Looks up a variable by walking up the call stack frames.
  Returns {:ok, value} if found, or {:error, :undefined_variable} if not found.
  """
  def lookup_variable({:ok, context}, name), do: lookup_variable(context, name)
  def lookup_variable({:error, _, _} = error, _name), do: error

  def lookup_variable(%__MODULE__{} = context, name) do
    case do_lookup_variable(name, context.current_frame, context) do
      {:ok, _value} = result -> result
      :error -> {:error, :undefined_variable}
    end
  end

  @doc """
  Declares a new variable in the current frame.
  Returns {:ok, context} if successful, or {:error, reason} if the variable already exists.
  """
  def declare_variable(context, name, value) do
    case context.current_frame do
      nil ->
        {:error, :no_active_frame}

      frame ->
        if Map.has_key?(frame.variables, name) do
          {:error, :variable_already_exists}
        else
          new_frame = Sparq.Frame.add_variable(frame, name, value)
          {:ok, update_current_frame(context, new_frame)}
        end
    end
  end

  @doc """
  Updates an existing variable in the nearest frame where it's defined.
  Returns {:ok, context} if successful, or {:error, reason} if the variable doesn't exist.
  """
  def update_variable(context, name, value) do
    case find_variable_frame(name, context.current_frame, context) do
      {:ok, frame} ->
        new_frame = Sparq.Frame.add_variable(frame, name, value)
        {:ok, update_frame_in_stack(context, frame.ref, new_frame)}

      :error ->
        {:error, :undefined_variable}
    end
  end

  @doc """
  Adds a subscriber to receive debug events.
  The subscriber will receive events as messages in the format:
  {:debug_event, event}
  """
  def subscribe(context, subscriber_pid) when is_pid(subscriber_pid) do
    %{context | subscribers: MapSet.put(context.subscribers, subscriber_pid)}
  end

  @doc """
  Removes a subscriber from debug event notifications.
  """
  def unsubscribe(context, subscriber_pid) when is_pid(subscriber_pid) do
    %{context | subscribers: MapSet.delete(context.subscribers, subscriber_pid)}
  end

  @doc """
  Updates the event mask to control which event types are generated.
  """
  def set_event_mask(context, mask) when is_integer(mask) do
    %{context | event_mask: mask}
  end

  @doc """
  Enables specific event types in the event mask.
  """
  def enable_events(context, event_types) do
    %{context | event_mask: Sparq.Debug.EventMask.enable(context.event_mask, event_types)}
  end

  @doc """
  Disables specific event types in the event mask.
  """
  def disable_events(context, event_types) do
    %{context | event_mask: Sparq.Debug.EventMask.disable(context.event_mask, event_types)}
  end

  @doc """
  Adds a debug event to the context and notifies subscribers if the event type is enabled.
  """
  def add_event(context, type, data \\ %{}, _opts \\ []) do
    if Sparq.Debug.EventMask.has_event?(context.event_mask, type) do
      event = create_event(context, type, data)
      context = add_event_to_history(context, event)
      notify_subscribers(context, event)
    else
      context
    end
  end

  defp create_event(context, type, data) do
    Sparq.Debug.Event.new(type, data,
      context_ref: context.ref,
      frame_ref: context.current_frame && context.current_frame.ref
    )
  end

  defp add_event_to_history(context, event) do
    %{context | event_history: :queue.in(event, context.event_history)}
  end

  defp notify_subscribers(context, event) do
    # Notify subscribers and clean up dead ones in one pass
    {live_subscribers, _dead_subscribers} =
      Enum.split_with(context.subscribers, &Process.alive?/1)

    Enum.each(live_subscribers, &send(&1, {:debug_event, event}))
    %{context | subscribers: MapSet.new(live_subscribers)}
  end

  @doc """
  Retrieves recent debug events from the event history.
  """
  def get_events(context, opts \\ []) do
    limit = Keyword.get(opts, :limit, :infinity)
    filter = Keyword.get(opts, :filter, fn _event -> true end)

    context.event_history
    |> :queue.to_list()
    |> Enum.filter(filter)
    |> case do
      events when is_integer(limit) -> Enum.take(events, limit)
      events -> events
    end
  end

  @doc """
  Clears the event history.
  """
  def clear_events(context) do
    %{context | event_history: :queue.new()}
  end

  @doc """
  Finalizes execution and updates timing.
  Similar to halt_execution but preserves error status if present.
  """
  def end_execution(%{status: :error} = context) do
    %{halt_execution(context) | status: :error}
  end

  def end_execution(context) do
    halt_execution(context)
  end

  @doc """
  Adds a trace event to the context.
  """
  def add_trace({:ok, context}, event), do: {:ok, add_trace(context, event)}
  def add_trace({:error, _, _} = error, _event), do: error

  def add_trace(%__MODULE__{} = context, event) do
    %{context | event_history: :queue.in(event, context.event_history)}
  end

  @doc """
  Declares a constant in the current frame.
  Similar to declare_variable but marks it as constant.
  """
  def declare_constant(context, name, value) do
    case context.current_frame do
      nil ->
        {:error, :no_active_frame}

      frame ->
        if Map.has_key?(frame.variables, name) do
          {:error, :variable_already_exists}
        else
          new_frame = Sparq.Frame.add_constant(frame, name, value)
          {:ok, update_current_frame(context, new_frame)}
        end
    end
  end

  @doc """
  Conditionally steps the debugger if in step mode.
  """
  def maybe_step(context, message, meta \\ %{})
  def maybe_step({:ok, context}, message, meta), do: {:ok, maybe_step(context, message, meta)}
  def maybe_step({:error, _, _} = error, _message, _meta), do: error

  def maybe_step(%__MODULE__{step_mode: true} = context, message, meta) do
    context
    |> add_event(:step_complete, %{message: message, meta: meta})
    |> increment_step_count()
  end

  def maybe_step(context, _message, _meta), do: context

  defp increment_step_count(context) do
    %{context | step_count: context.step_count + 1}
  end

  defp do_lookup_variable(_name, nil, _context), do: :error

  defp do_lookup_variable(name, frame, context) do
    name = to_string(name)

    case Map.get(frame.variables, name) do
      nil ->
        case frame.parent_ref do
          nil ->
            :error

          parent_ref ->
            parent_frame = find_frame_in_stack(parent_ref, context)

            case parent_frame do
              nil -> :error
              frame -> do_lookup_variable(name, frame, context)
            end
        end

      {:const, _} = value ->
        {:ok, value}

      value ->
        {:ok, value}
    end
  end

  defp find_frame_in_stack(ref, context) do
    context.call_stack
    |> :queue.to_list()
    |> Enum.find(&(&1.ref == ref))
  end

  defp find_variable_frame(_name, nil, _context), do: :error

  defp find_variable_frame(name, frame, context) do
    name = to_string(name)

    if Map.has_key?(frame.variables, name) do
      {:ok, frame}
    else
      case frame.parent_ref do
        nil ->
          :error

        parent_ref ->
          parent_frame = find_frame_in_stack(parent_ref, context)

          case parent_frame do
            nil -> :error
            frame -> find_variable_frame(name, frame, context)
          end
      end
    end
  end

  defp update_current_frame(context, new_frame) do
    new_stack =
      :queue.to_list(context.call_stack)
      |> Enum.map(fn f -> if f.ref == new_frame.ref, do: new_frame, else: f end)
      |> :queue.from_list()

    %{context | current_frame: new_frame, call_stack: new_stack}
  end

  defp update_frame_in_stack(context, frame_ref, new_frame) do
    if context.current_frame.ref == frame_ref do
      update_current_frame(context, new_frame)
    else
      new_stack =
        :queue.to_list(context.call_stack)
        |> Enum.map(&if(&1.ref == frame_ref, do: new_frame, else: &1))
        |> :queue.from_list()

      %{context | call_stack: new_stack}
    end
  end

  # Private helper to format frame traces
  defp format_frame_trace(frame) do
    location = if frame.file, do: "#{frame.file}:#{frame.line}", else: "unknown"
    "#{frame.type} #{frame.name} at #{location}"
  end

  @doc """
  Adds a breakpoint at a specific location.
  """
  def add_breakpoint(%__MODULE__{} = context, module, line) do
    %{context | breakpoints: MapSet.put(context.breakpoints, {module, line})}
  end

  @doc """
  Removes a breakpoint from a specific location.
  """
  def remove_breakpoint(%__MODULE__{} = context, module, line) do
    %{context | breakpoints: MapSet.delete(context.breakpoints, {module, line})}
  end

  @doc """
  Checks if a breakpoint exists at the specified location.
  """
  def has_breakpoint?(%__MODULE__{} = context, module, line) do
    MapSet.member?(context.breakpoints, {module, line})
  end

  @doc """
  Enables debug mode for the context.
  """
  def enable_debug_mode(%__MODULE__{} = context) do
    %{context | debug_mode: true}
  end

  @doc """
  Disables debug mode for the context.
  """
  def disable_debug_mode(%__MODULE__{} = context) do
    %{context | debug_mode: false}
  end

  @doc """
  Enables step-by-step execution mode.
  """
  def enable_step_mode(%__MODULE__{} = context) do
    %{context | step_mode: true}
  end

  @doc """
  Disables step-by-step execution mode.
  """
  def disable_step_mode(%__MODULE__{} = context) do
    %{context | step_mode: false}
  end
end
