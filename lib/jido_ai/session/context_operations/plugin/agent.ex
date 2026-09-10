defmodule Jido.AI.Context.Operations.Plugin.Agent do
  @moduledoc false
  use Jido.Agent.Plugin

  alias Jido.AI.Context.Operations, as: Ops

  @impl Jido.Agent.Plugin
  def state_spec(opts),
    do: {Ops.key(), Zoi.map() |> Zoi.refine({Ops, :validate_state, [opts[:profiles]]}) |> Zoi.default(%{})}

  @impl Jido.Agent.Plugin
  def directives(_opts), do: [Ops.Change]

  @impl Jido.Agent.Plugin
  def validate_directive(%Ops.Change{} = change, opts) do
    with :ok <- Ops.validate_state(%{change.profile_id => change.value}, opts[:profiles], nil),
         do: {:ok, change}
  end

  @impl Jido.Agent.Plugin
  def update_state(state, directives, _opts) do
    {:ok,
     Enum.reduce(directives, state, fn change, current ->
       Map.put(current, change.profile_id, change.value)
     end)}
  end
end
