defmodule Sparq.Frame do
  @moduledoc """
  Represents a single execution frame on the call stack.
  Handles variable scoping and frame-level state.
  """

  defstruct [
    # Frame Identity
    # Unique frame reference
    ref: nil,
    # :root | :block | :function | :module
    type: nil,
    # Function/block name
    name: nil,

    # Frame Location
    # Source file
    file: nil,
    # Line number
    line: nil,
    # Module name
    module: nil,

    # Frame Data
    # Local variables
    variables: %{},
    # Function arguments
    args: nil,
    # Return value
    return_value: nil,

    # Frame Relationships
    # Reference of parent frame
    parent_ref: nil,
    # Stack depth
    depth: 0,

    # Frame Timing
    # Push time
    entered_at: nil,
    # Pop time
    exited_at: nil,

    # Frame Status & Debug
    # :active | :completed | :error
    status: :active,
    # Debug metadata
    debug_data: %{},
    # Frame tracing flag
    traced: false
  ]

  @type frame_type :: :root | :block | :function | :module
  @type frame_status :: :active | :completed | :error
  @type t :: %__MODULE__{}

  @doc """
  Creates a new stack frame with optional configuration.
  """
  def new(opts \\ []) do
    opts =
      Keyword.update(opts, :type, :block, fn
        type when is_atom(type) -> type
        %__MODULE__{type: type} -> type
        _ -> :block
      end)

    frame = struct(__MODULE__, opts)
    %{frame | ref: make_ref(), entered_at: :erlang.monotonic_time(:nanosecond)}
  end

  @doc """
  Adds a variable to the frame's scope.
  """
  def add_variable(frame, name, value) do
    %{frame | variables: Map.put(frame.variables, to_string(name), value)}
  end

  @doc """
  Retrieves a variable from the frame's scope.
  Also handles module objects which have functions and state instead of variables.
  """
  def get_variable(frame, name) do
    name = to_string(name)

    cond do
      # Handle module objects (plain maps)
      is_map(frame) && not is_struct(frame) && Map.get(frame, :type) == :module ->
        Map.get(frame.functions, name) || Map.get(frame.state || %{}, name)

      # Handle Frame structs
      is_struct(frame, __MODULE__) ->
        Map.get(frame.variables, name)

      true ->
        nil
    end
  end

  @doc """
  Sets the return value and marks frame as completed.
  """
  def complete_frame(frame, return_value \\ nil) do
    %{
      frame
      | status: :completed,
        return_value: return_value,
        exited_at: :erlang.monotonic_time(:nanosecond)
    }
  end

  @doc """
  Converts the frame to a map representation suitable for serialization or inspection.
  Includes all relevant frame data except internal references.
  """
  def to_map(frame) do
    %{
      type: frame.type,
      name: frame.name,
      location: %{
        file: frame.file,
        line: frame.line,
        module: frame.module
      },
      variables: frame.variables,
      args: frame.args,
      return_value: frame.return_value,
      depth: frame.depth,
      timing: get_timing(frame),
      status: frame.status,
      debug_data: frame.debug_data
    }
  end

  @doc """
  Returns timing information for the frame in nanoseconds.
  Includes entered_at, exited_at (if completed), and duration (if completed).
  """
  def get_timing(frame) do
    base = %{entered_at: frame.entered_at}

    case frame.exited_at do
      nil ->
        base

      exited_at ->
        Map.merge(base, %{
          exited_at: exited_at,
          duration_ns: exited_at - frame.entered_at
        })
    end
  end

  @doc """
  Returns a map of all variables in the frame's scope with their values.
  Optionally accepts a filter function to select specific variables.
  """
  def get_variables(frame, filter_fn \\ fn _name, _value -> true end) do
    frame.variables
    |> Enum.filter(fn {name, value} -> filter_fn.(name, value) end)
    |> Map.new()
  end

  @doc """
  Adds a constant to the frame's scope.
  Similar to add_variable but marks it as constant.
  """
  def add_constant(frame, name, value) do
    %{frame | variables: Map.put(frame.variables, to_string(name), {:const, value})}
  end
end
