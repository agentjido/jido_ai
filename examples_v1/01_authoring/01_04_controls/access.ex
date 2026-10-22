defmodule JidoAI.Examples.Controls.Access do
  @moduledoc "A host-supplied authorization decision gates model work."
  @behaviour Jido.AI.Control

  @impl true
  def check(_query, context) do
    if Map.get(context, :authorized) == true,
      do: :ok,
      else: Jido.AI.Profile.error("access", "Case access denied")
  end
end
