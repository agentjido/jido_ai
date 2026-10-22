defmodule Jido.AI.Thread.Control.Plugin do
  @moduledoc false
  use Jido.Plugin

  @impl true
  defdelegate state_spec(opts), to: Jido.AI.Thread.Control.Plugin.Agent

  @impl true
  defdelegate directives(opts), to: Jido.AI.Thread.Control.Plugin.Agent

  @impl true
  defdelegate reduce(reduction, opts), to: Jido.AI.Thread.Control.Plugin.Agent
end
