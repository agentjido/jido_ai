defmodule Sparq.Debug do
  @moduledoc """
  Enhanced debugging and introspection capabilities for Sparq interpreter.
  Provides comprehensive debugging features including:
  - Event-based debugging system
  - Step-by-step execution
  - Variable watching
  - Breakpoints
  - Stack frame inspection
  - Performance profiling
  - Memory tracking
  """

  alias Sparq.{Context, Frame, Error}

  require Logger

  @doc """
  Sets debug mode for a context.
  Enables event tracking and basic debug features.
  """
  def enable(%Context{} = ctx) do
    Context.enable_debug_mode(ctx)
  end

  @doc """
  Disables debug mode for a context
  """
  def disable(%Context{} = ctx) do
    Context.disable_debug_mode(ctx)
  end

  @doc """
  Enables step-by-step execution mode
  """
  def enable_stepping(%Context{} = ctx) do
    Context.enable_step_mode(ctx)
  end

  @doc """
  Disables step-by-step execution
  """
  def disable_stepping(%Context{} = ctx) do
    Context.disable_step_mode(ctx)
  end

  @doc """
  Adds a breakpoint at a specific location
  """
  def add_breakpoint(%Context{} = ctx, module, line) do
    Context.add_breakpoint(ctx, module, line)
  end

  @doc """
  Removes a breakpoint
  """
  def remove_breakpoint(%Context{} = ctx, module, line) do
    Context.remove_breakpoint(ctx, module, line)
  end

  @doc """
  Checks if a breakpoint exists at the current location
  """
  def has_breakpoint?(%Context{} = ctx, module, line) do
    Context.has_breakpoint?(ctx, module, line)
  end

  @doc """
  Adds a debug event subscriber
  """
  def subscribe(%Context{} = ctx, subscriber_pid) when is_pid(subscriber_pid) do
    Context.subscribe(ctx, subscriber_pid)
  end

  @doc """
  Removes a debug event subscriber
  """
  def unsubscribe(%Context{} = ctx, subscriber_pid) when is_pid(subscriber_pid) do
    Context.unsubscribe(ctx, subscriber_pid)
  end

  @doc """
  Steps execution and pauses for debugging if needed
  Returns updated context
  """
  def maybe_step(%Context{debug_mode: true} = ctx, message, meta) do
    ctx = Context.add_event(ctx, :step_complete, %{message: message, meta: meta})

    cond do
      ctx.step_mode ->
        handle_step(ctx, message, meta)

      should_break?(ctx, meta) ->
        handle_breakpoint(ctx, message, meta)

      true ->
        ctx
    end
  end

  def maybe_step(ctx, _message, _meta), do: ctx

  @doc """
  Gets the current stack trace with source locations
  """
  def get_stack_trace(%Context{} = ctx) do
    Context.get_stack_trace(ctx)
  end

  @doc """
  Gets variable values from the current frame
  """
  def get_variables(%Context{current_frame: frame}) when not is_nil(frame) do
    Frame.get_variables(frame)
  end

  def get_variables(_), do: %{}

  @doc """
  Gets debug events matching optional filters
  """
  def get_events(%Context{} = ctx, opts \\ []) do
    Context.get_events(ctx, opts)
  end

  @doc """
  Clears debug event history
  """
  def clear_events(%Context{} = ctx) do
    Context.clear_events(ctx)
  end

  # Private helper functions

  defp should_break?(%Context{} = ctx, meta) do
    has_breakpoint?(ctx, meta[:module], meta[:line])
  end

  defp handle_step(ctx, message, meta) do
    # Display debug info and wait for input
    display_debug_info(ctx, message, meta)
    handle_debug_command(ctx)
  end

  defp handle_breakpoint(ctx, message, meta) do
    # Show breakpoint hit and debug info
    Logger.info("Breakpoint hit at #{meta[:module]}:#{meta[:line]}")
    display_debug_info(ctx, message, meta)
    handle_debug_command(ctx)
  end

  defp display_debug_info(ctx, message, meta) do
    info = """

    #{message}
    Location: #{meta[:module]}:#{meta[:line]}
    Variables: #{inspect(get_variables(ctx), pretty: true)}
    Stack Trace:
    #{Enum.join(get_stack_trace(ctx), "\n")}

    Commands: continue (c), step (s), variables (v), trace (t), help (h), quit (q)
    """

    IO.puts(info)
  end

  defp handle_debug_command(ctx) do
    case IO.gets("debug> ") |> String.trim() do
      "c" ->
        ctx

      "s" ->
        ctx

      "v" ->
        # credo:disable-for-next-line Credo.Check.Warning.IoInspect
        IO.inspect(get_variables(ctx), pretty: true)
        handle_debug_command(ctx)

      "t" ->
        IO.puts(Enum.join(get_stack_trace(ctx), "\n"))
        handle_debug_command(ctx)

      "h" ->
        show_help()
        handle_debug_command(ctx)

      "q" ->
        raise Error.new(:debug_quit, "Debugging session terminated by user")

      _ ->
        handle_debug_command(ctx)
    end
  end

  defp show_help do
    help = """
    Debug Commands:
    c - Continue execution
    s - Step to next expression
    v - Show local variables
    t - Show stack trace
    h - Show this help
    q - Quit debugging session
    """

    IO.puts(help)
  end
end
