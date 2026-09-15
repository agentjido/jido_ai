defmodule Jido.AI.Context.Operations.Apply do
  @moduledoc false
  use Jido.Action, name: "ai_context_modify"

  @impl Jido.Action
  def run(params, context) do
    Jido.AI.Error.capture(fn ->
      with {:ok, context} <- Jido.AI.Session.Plugin.context(context),
           do: Jido.AI.Context.Operations.modify(params, context)
    end)
  end
end
