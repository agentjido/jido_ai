defmodule Depot.Registry do
  @moduledoc """
  Elixir registry to register adapter instances on for adapters, which need processes.

  ## Registration

  Register instances with the via tuple of: `Depot.Registry.via(adapter, name)`

  """

  @doc false
  def child_spec(_) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end

  @doc false
  def via(adapter, name) do
    {:via, Registry, {__MODULE__, {adapter, name}}}
  end
end
