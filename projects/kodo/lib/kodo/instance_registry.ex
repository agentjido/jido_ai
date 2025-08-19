defmodule Kodo.InstanceRegistry do
  @moduledoc """
  Registry wrapper for managing Kodo instance components and resources.

  This module provides a clean interface for registering and looking up
  instance-specific resources like VFS mount tables, session registries,
  and other per-instance data.
  """

  @registry_name Kodo.InstanceRegistry

  @doc """
  Registers a resource for an instance.
  """
  @spec register(instance :: term(), key :: term(), value :: term()) :: :ok | {:error, term()}
  def register(instance, key, value) do
    registry_key = {instance, key}

    case Registry.register(@registry_name, registry_key, value) do
      {:ok, _} -> :ok
      {:error, {:already_registered, _}} -> {:error, :already_registered}
      error -> error
    end
  end

  @doc """
  Looks up a resource for an instance.
  """
  @spec lookup(instance :: term(), key :: term()) :: {:ok, term()} | {:error, :not_found}
  def lookup(instance, key) do
    registry_key = {instance, key}

    case Registry.lookup(@registry_name, registry_key) do
      [{_pid, value}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Unregisters a resource for an instance.
  """
  @spec unregister(instance :: term(), key :: term()) :: :ok
  def unregister(instance, key) do
    registry_key = {instance, key}
    Registry.unregister(@registry_name, registry_key)
  end

  @doc """
  Lists all resources for an instance.
  """
  @spec list(instance :: term()) :: [{key :: term(), value :: term()}]
  def list(instance) do
    Registry.select(@registry_name, [
      {{{instance, :"$1"}, :_, :"$2"}, [], [{{:"$1", :"$2"}}]}
    ])
  end
end
