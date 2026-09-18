defmodule Jido.AI.Configuration.Change do
  @moduledoc "A validated tool, prompt or base context change for one declared AI profile."
  defstruct [:profile_id, :operation, :value]
  use Jido.Agent.Directive

  @impl Jido.Agent.Directive
  def validate(%__MODULE__{profile_id: id, operation: operation, value: value} = change) do
    valid =
      is_atom(id) and not is_nil(id) and
        case operation do
          :register -> is_atom(value) and not is_nil(value)
          :tools -> is_list(value)
          :tool_context -> is_map(value) and not is_struct(value)
          op when op in [:unregister, :prompt] -> is_binary(value)
          _ -> false
        end

    if valid do
      case Jido.Action.validate_static_data(change) do
        :ok -> {:ok, change}
        error -> error
      end
    else
      Jido.AI.Profile.error("configuration", "Invalid configuration change")
    end
  end

  def validate(_), do: Jido.AI.Profile.error("configuration", "Expected a configuration directive")
end
