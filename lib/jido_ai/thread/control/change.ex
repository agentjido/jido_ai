defmodule Jido.AI.Thread.Control.Change do
  @moduledoc false
  use Jido.Agent.Directive
  defstruct [:profile_id, :value]

  @impl Jido.Agent.Directive
  def validate(%__MODULE__{profile_id: id, value: value} = change)
      when is_atom(id) and not is_nil(id) and is_map(value) do
    case Jido.Action.validate_static_data(value) do
      :ok -> {:ok, change}
      error -> error
    end
  end

  def validate(_), do: {:error, :invalid_context_change}
end
