defmodule Jido.AI.Thread.Control.Plugin.Agent do
  @moduledoc false
  alias Jido.AI.Thread.Control, as: Ops

  def state_spec(opts),
    do: {Ops.key(), Zoi.map() |> Zoi.refine({Ops, :validate_state, [opts[:profiles]]}) |> Zoi.default(%{})}

  def directives(_opts), do: [Ops.Change]

  def reduce(reduction, opts) do
    reduction.directives
    |> Enum.filter(&match?(%Ops.Change{}, &1))
    |> Enum.reduce_while({:ok, reduction.plugin_state}, fn change, {:ok, state} ->
      case Ops.validate_state(%{change.profile_id => change.value}, opts[:profiles], nil) do
        :ok -> {:cont, {:ok, Map.put(state, change.profile_id, change.value)}}
        error -> {:halt, error}
      end
    end)
  end
end
