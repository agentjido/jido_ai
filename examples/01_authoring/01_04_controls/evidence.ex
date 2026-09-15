defmodule JidoAI.Examples.Controls.Evidence do
  @moduledoc "A simple output policy; a marker is not proof of factual accuracy."
  @behaviour Jido.AI.Control

  @impl true
  def check(answer, _context) do
    if is_binary(answer) and String.contains?(answer, "[evidence]"),
      do: :ok,
      else: Jido.AI.Profile.error("evidence", "Answer has no evidence marker")
  end
end
