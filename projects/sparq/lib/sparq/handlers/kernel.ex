defmodule Sparq.Handlers.Kernel do
  @moduledoc """
  Handles core Elixir Kernel operations in the Sparq language.
  """

  use Sparq.Handlers.Behaviour

  @impl true
  def handle(:is_tuple, _meta, [term], ctx) do
    {is_tuple(term), ctx}
  end

  def handle(:is_atom, _meta, [term], ctx) do
    {is_atom(term), ctx}
  end

  def handle(:is_binary, _meta, [term], ctx) do
    {is_binary(term), ctx}
  end

  def handle(:is_boolean, _meta, [term], ctx) do
    {is_boolean(term), ctx}
  end

  def handle(:is_float, _meta, [term], ctx) do
    {is_float(term), ctx}
  end

  def handle(:is_function, _meta, [term], ctx) do
    {is_function(term), ctx}
  end

  def handle(:is_integer, _meta, [term], ctx) do
    {is_integer(term), ctx}
  end

  def handle(:is_list, _meta, [term], ctx) do
    {is_list(term), ctx}
  end

  def handle(:is_map, _meta, [term], ctx) do
    {is_map(term), ctx}
  end

  def handle(:is_nil, _meta, [term], ctx) do
    {is_nil(term), ctx}
  end

  def handle(:is_number, _meta, [term], ctx) do
    {is_number(term), ctx}
  end

  def handle(:is_pid, _meta, [term], ctx) do
    {is_pid(term), ctx}
  end

  def handle(:is_reference, _meta, [term], ctx) do
    {is_reference(term), ctx}
  end

  def handle(:tuple_size, _meta, [tuple], ctx) when is_tuple(tuple) do
    {tuple_size(tuple), ctx}
  end

  def handle(:elem, _meta, [tuple, index], ctx) when is_tuple(tuple) and is_integer(index) do
    try do
      {elem(tuple, index), ctx}
    rescue
      ArgumentError -> raise "invalid index"
    end
  end

  def handle(:put_elem, _meta, [tuple, index, value], ctx)
      when is_tuple(tuple) and is_integer(index) do
    try do
      {put_elem(tuple, index, value), ctx}
    rescue
      ArgumentError -> raise "invalid index"
    end
  end

  def handle(:system_time, _meta, [], ctx) do
    {System.system_time(), ctx}
  end

  def handle(:system_time, _meta, [unit], ctx) when is_atom(unit) do
    try do
      {System.system_time(unit), ctx}
    rescue
      ArgumentError -> raise "invalid time unit"
    end
  end

  def handle(:monotonic_time, _meta, [], ctx) do
    {System.monotonic_time(), ctx}
  end

  def handle(:monotonic_time, _meta, [unit], ctx) when is_atom(unit) do
    try do
      {System.monotonic_time(unit), ctx}
    rescue
      ArgumentError -> raise "invalid time unit"
    end
  end

  @impl true
  def validate(:tuple_size, [tuple]) when not is_tuple(tuple),
    do: {:error, :tuple}

  def validate(:elem, [tuple, index]) when not (is_tuple(tuple) and is_integer(index)),
    do: {:error, :index}

  def validate(:put_elem, [tuple, index, _value])
      when not (is_tuple(tuple) and is_integer(index)),
      do: {:error, :index}

  def validate(:system_time, [unit]) when not is_atom(unit),
    do: {:error, :time_unit}

  def validate(:monotonic_time, [unit]) when not is_atom(unit),
    do: {:error, :time_unit}

  def validate(_op, _args), do: :ok
end
