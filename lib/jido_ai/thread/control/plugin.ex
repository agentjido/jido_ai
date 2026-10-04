defmodule Jido.AI.Thread.Control.Plugin do
  @moduledoc false
  use Jido.Plugin

  defdelegate state_spec(opts), to: Jido.AI.Thread.Control.Plugin.Agent
  defdelegate directives(opts), to: Jido.AI.Thread.Control.Plugin.Agent
  defdelegate reduce(reduction, opts), to: Jido.AI.Thread.Control.Plugin.Agent
end
