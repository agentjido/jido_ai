defmodule Jido.AI.Context.Operations.Apply do
  @moduledoc false
  use Jido.Action, name: "ai_context_modify"

  @impl Jido.Action
  def run(params, context) do
    case Jido.AI.Error.capture(fn -> Jido.AI.Context.Operations.modify(params, context) end) do
      {:error, _error} when is_map_key(params, :legacy?) -> {:ok, context.agent_state}
      result -> result
    end
  end
end
