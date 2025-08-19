defmodule Sparq.Debug.EventMask do
  @moduledoc """
  Provides bitfield-based event filtering for debug events.
  Each event type has a corresponding bit in the mask.
  """

  # Debug event type bits
  # Frame entry/exit
  @frame_events 0x0001
  # Variable read/write
  @variable_events 0x0002
  # Error events
  @error_events 0x0004
  # Step completion
  @step_events 0x0008
  # Module load/unload
  @module_events 0x0010
  # Function call/return
  @function_events 0x0020
  # Breakpoint hits
  @breakpoint_events 0x0040

  @doc """
  Returns a mask that allows all event types.
  """
  def all(), do: 0xFFFFFFFF

  @doc """
  Returns a mask that blocks all event types.
  """
  def none(), do: 0x00000000

  @doc """
  Returns a mask for frame-related events only.
  """
  def frames_only(), do: @frame_events

  @doc """
  Returns a mask for variable access events only.
  """
  def variables_only(), do: @variable_events

  @doc """
  Returns a mask for error events only.
  """
  def errors_only(), do: @error_events

  @doc """
  Returns a mask for step events only.
  """
  def steps_only(), do: @step_events

  @doc """
  Returns a mask for module events only.
  """
  def modules_only(), do: @module_events

  @doc """
  Returns a mask for function events only.
  """
  def functions_only(), do: @function_events

  @doc """
  Returns a mask for breakpoint events only.
  """
  def breakpoints_only(), do: @breakpoint_events

  @doc """
  Checks if a given event type is enabled in the mask.
  """
  def has_event?(mask, event_type) do
    Bitwise.band(mask, event_bit(event_type)) != 0
  end

  @doc """
  Enables specific event types in the mask.
  """
  def enable(mask, event_types) when is_list(event_types) do
    Enum.reduce(event_types, mask, fn type, acc ->
      Bitwise.bor(acc, event_bit(type))
    end)
  end

  def enable(mask, event_type) do
    Bitwise.bor(mask, event_bit(event_type))
  end

  @doc """
  Disables specific event types in the mask.
  """
  def disable(mask, event_types) when is_list(event_types) do
    Enum.reduce(event_types, mask, fn type, acc ->
      Bitwise.band(acc, Bitwise.bnot(event_bit(type)))
    end)
  end

  def disable(mask, event_type) do
    Bitwise.band(mask, Bitwise.bnot(event_bit(event_type)))
  end

  # Private helpers

  defp event_bit(:frame_entry), do: @frame_events
  defp event_bit(:frame_exit), do: @frame_events
  defp event_bit(:variable_read), do: @variable_events
  defp event_bit(:variable_write), do: @variable_events
  defp event_bit(:error), do: @error_events
  defp event_bit(:step_complete), do: @step_events
  defp event_bit(:module_load), do: @module_events
  defp event_bit(:module_unload), do: @module_events
  defp event_bit(:function_call), do: @function_events
  defp event_bit(:function_return), do: @function_events
  defp event_bit(:breakpoint_hit), do: @breakpoint_events
end
