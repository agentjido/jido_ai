defmodule Sparq.Handlers.Registry do
  @moduledoc """
  Registry for operation handlers in the Sparq system.
  Provides a central location for registering and looking up handlers for different operations.
  """

  @doc """
  Gets the appropriate handler module for an operation.
  Returns the module that should handle the given operation.
  """
  def get_handler(op) when op in [:add, :subtract, :multiply, :divide, :+, :-, :*, :/] do
    Sparq.Handlers.Builtins
  end

  def get_handler(:print), do: Sparq.Handlers.IO
  def get_handler(:bind), do: Sparq.Handlers.Variables

  def get_handler(op)
      when op in [
             :string,
             :string_concat,
             :atom,
             :atom_to_string,
             :list,
             :cons,
             :head,
             :tail,
             :empty?,
             :map,
             :map_put,
             :map_get,
             :map_delete,
             true,
             false,
             :and,
             :or,
             :not,
             nil,
             :nil?,
             :type_of,
             :tuple
           ] do
    Sparq.Handlers.Types
  end

  def get_handler(op)
      when op in [
             :node,
             :self,
             :spawn,
             :spawn_link,
             :send,
             :process_info,
             :process_flag,
             :make_ref,
             :monitor,
             :demonitor,
             :is_pid,
             :is_reference,
             :is_port,
             :is_tuple,
             :is_list,
             :is_number,
             :is_atom,
             :is_binary,
             :is_boolean,
             :is_nil,
             :tuple_size,
             :elem,
             :put_elem,
             :system_time,
             :monotonic_time
           ] do
    Sparq.Handlers.Kernel
  end

  def get_handler(:list_map), do: Sparq.Handlers.Collection
  def get_handler(:list_filter), do: Sparq.Handlers.Collection
  def get_handler(:list_reduce), do: Sparq.Handlers.Collection
  def get_handler(:map_keys), do: Sparq.Handlers.Collection
  def get_handler(:map_values), do: Sparq.Handlers.Collection
  def get_handler(module) when is_atom(module), do: module

  def get_handler(op) do
    raise ArgumentError, "No handler found for operation: #{inspect(op)}"
  end
end
