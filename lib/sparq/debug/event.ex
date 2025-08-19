defmodule Sparq.Debug.Event do
  @moduledoc """
  Defines the structure and types for debug events in the Sparq system.
  Events are used to track execution flow, variable access, errors, and other
  debug-related information.
  """

  defstruct [
    # Type of debug event
    type: nil,
    # When event occurred
    timestamp: nil,
    # Context reference
    context_ref: nil,
    # Frame reference (if applicable)
    frame_ref: nil,
    # Event-specific data
    data: %{},
    # Basic process information
    process_info: nil
  ]

  @type event_type ::
          :frame_entry
          | :frame_exit
          | :variable_read
          | :variable_write
          | :error
          | :breakpoint_hit
          | :step_complete
          | :module_load
          | :module_unload
          | :function_call
          | :function_return

  @type t :: %__MODULE__{
          type: event_type(),
          timestamp: integer(),
          context_ref: reference() | nil,
          frame_ref: reference() | nil,
          data: map(),
          process_info: map() | nil
        }

  @doc """
  Creates a new debug event with the given type and data.
  Automatically adds timestamp and process information.
  """
  def new(type, data \\ %{}, opts \\ []) do
    %__MODULE__{
      type: type,
      timestamp: System.monotonic_time(:nanosecond),
      context_ref: Keyword.get(opts, :context_ref),
      frame_ref: Keyword.get(opts, :frame_ref),
      data: data,
      process_info: get_process_info()
    }
  end

  @doc """
  Formats an event for human-readable output.
  """
  def format(%__MODULE__{} = event) do
    location =
      case {event.context_ref, event.frame_ref} do
        {nil, nil} -> "unknown"
        {ctx, nil} -> "context:#{inspect(ctx)}"
        {nil, frame} -> "frame:#{inspect(frame)}"
        {ctx, frame} -> "context:#{inspect(ctx)} frame:#{inspect(frame)}"
      end

    timestamp = DateTime.from_unix!(event.timestamp, :nanosecond)

    "#{Calendar.strftime(timestamp, "%H:%M:%S.%f")} [#{event.type}] at #{location} - #{format_data(event.data)}"
  end

  # Private helpers

  defp get_process_info do
    info = Process.info(self(), [:registered_name, :status, :message_queue_len])

    %{
      pid: self(),
      registered_name: info[:registered_name],
      status: info[:status],
      message_queue_len: info[:message_queue_len]
    }
  end

  defp format_data(data) when is_map(data) do
    Enum.map_join(data, ", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)
  end

  defp format_data(data), do: inspect(data)
end
