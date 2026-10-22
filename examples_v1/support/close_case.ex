defmodule JidoAI.Examples.Support.CloseCase do
  @moduledoc false
  use Jido.Action, name: "ai_example_close", schema: Zoi.object(%{reason: Zoi.string()})
  def run(%{reason: reason}, %{agent_state: state}), do: {:ok, %{state | case_id: reason}}
end
