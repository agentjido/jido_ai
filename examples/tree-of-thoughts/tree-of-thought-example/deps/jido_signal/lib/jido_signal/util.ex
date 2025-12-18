defmodule Jido.Signal.Util do
  @moduledoc """
  A collection of utility functions for the Jido framework.

  This module provides various helper functions that are used throughout the Jido framework,
  including:

  - ID generation
  - Name validation
  - Error handling
  - Logging utilities

  These utilities are designed to support common operations and maintain consistency
  across the Jido ecosystem. They encapsulate frequently used patterns and provide
  a centralized location for shared functionality.

  Many of the functions in this module are used internally by other Jido modules,
  but they can also be useful for developers building applications with Jido.
  """

  @type server :: pid() | atom() | binary() | {name :: atom() | binary(), registry :: module()}

  @doc """
  Creates a via tuple for process registration with a registry.

  ## Parameters

  - name: The name to register (atom, string, or {name, registry} tuple)
  - opts: Options list
    - :registry - The registry module to use (defaults to Jido.Signal.Registry)

  ## Returns

  A via tuple for use with process registration

  ## Examples

      iex> Jido.Signal.Util.via_tuple(:my_process)
      {:via, Registry, {Jido.Signal.Registry, "my_process"}}

      iex> Jido.Signal.Util.via_tuple(:my_process, registry: MyRegistry)
      {:via, Registry, {MyRegistry, "my_process"}}

      iex> Jido.Signal.Util.via_tuple({:my_process, MyRegistry})
      {:via, Registry, {MyRegistry, "my_process"}}
  """
  @spec via_tuple(server(), keyword()) :: {:via, Registry, {module(), String.t()}}
  def via_tuple(name_or_tuple, opts \\ [])

  def via_tuple({name, registry}, _opts) when is_atom(registry) do
    name = if is_atom(name), do: Atom.to_string(name), else: name
    {:via, Registry, {registry, name}}
  end

  def via_tuple(name, opts) do
    registry = Keyword.get(opts, :registry, Jido.Signal.Registry)
    name = if is_atom(name), do: Atom.to_string(name), else: name
    {:via, Registry, {registry, name}}
  end

  @doc """
  Finds a process by name, pid, or {name, registry} tuple.

  ## Parameters

  - server: The process identifier (pid, name, or {name, registry} tuple)
  - opts: Options list
    - :registry - The registry module to use (defaults to Jido.Signal.Registry)

  ## Returns

  - `{:ok, pid}` if process is found
  - `{:error, :not_found}` if process is not found

  ## Examples

      iex> Jido.Signal.Util.whereis(pid)
      {:ok, #PID<0.123.0>}

      iex> Jido.Signal.Util.whereis(:my_process)
      {:ok, #PID<0.124.0>}

      iex> Jido.Signal.Util.whereis({:my_process, MyRegistry})
      {:ok, #PID<0.125.0>}
  """
  @spec whereis(server(), keyword()) :: {:ok, pid()} | {:error, :not_found}
  def whereis(server, opts \\ [])

  def whereis(pid, _opts) when is_pid(pid), do: {:ok, pid}

  def whereis({name, registry}, _opts) when is_atom(registry) do
    name = if is_atom(name), do: Atom.to_string(name), else: name

    case Registry.lookup(registry, name) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  def whereis(name, opts) do
    registry = Keyword.get(opts, :registry, Jido.Signal.Registry)
    name = if is_atom(name), do: Atom.to_string(name), else: name

    case Registry.lookup(registry, name) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end
