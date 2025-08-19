defmodule Sparq.Handlers.Collection do
  @moduledoc """
  Standard library expansions for list and map utilities:
  :list_map, :list_filter, :list_reduce, :map_keys, :map_values
  """

  use Sparq.Handlers.Behaviour

  def handle(:list_map, _meta, [fun, list], ctx) when is_function(fun, 1) and is_list(list) do
    result = Enum.map(list, &fun.(&1))
    {result, ctx}
  end

  def handle(:list_filter, _meta, [fun, list], ctx) when is_function(fun, 1) and is_list(list) do
    result = Enum.filter(list, &fun.(&1))
    {result, ctx}
  end

  def handle(:list_reduce, _meta, [fun, acc, list], ctx)
      when is_function(fun, 2) and is_list(list) do
    result = Enum.reduce(list, acc, fn elem, accum -> fun.(elem, accum) end)
    {result, ctx}
  end

  def handle(:map_keys, _meta, [map], ctx) when is_map(map) do
    {Map.keys(map), ctx}
  end

  def handle(:map_values, _meta, [map], ctx) when is_map(map) do
    {Map.values(map), ctx}
  end

  # Fallback
  def handle(op, _meta, args, _ctx) do
    raise ArgumentError, "Unknown collection operation #{inspect(op)} with args #{inspect(args)}"
  end

  # Validation
  def validate(:list_map, [fun, list]) do
    cond do
      not is_function(fun, 1) -> {:error, :invalid_function_arity}
      not is_list(list) -> {:error, :invalid_list}
      true -> :ok
    end
  end

  def validate(:list_filter, [fun, list]) do
    cond do
      not is_function(fun, 1) -> {:error, :invalid_function_arity}
      not is_list(list) -> {:error, :invalid_list}
      true -> :ok
    end
  end

  def validate(:list_reduce, [fun, _acc, list]) do
    cond do
      not is_function(fun, 2) -> {:error, :invalid_function_arity}
      not is_list(list) -> {:error, :invalid_list}
      true -> :ok
    end
  end

  def validate(:map_keys, [map]) do
    if is_map(map), do: :ok, else: {:error, :invalid_map}
  end

  def validate(:map_values, [map]) do
    if is_map(map), do: :ok, else: {:error, :invalid_map}
  end

  def validate(_op, _args), do: :ok
end
