defmodule Jido.AI.Thread.Control.Apply do
  @moduledoc false
  use Jido.Action, name: "ai_context_modify"

  @impl Jido.Action
  def run(params, context) do
    Jido.AI.Error.capture(fn ->
      with {:ok, context} <- Jido.AI.Orchestration.Plugin.context(context),
           do: Jido.AI.Thread.Control.modify(params, context)
    end)
  end
end
