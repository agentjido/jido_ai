defmodule JidoAI.Examples.Support.SetCase do
  use Jido.Action, name: "capabilities_set_case", schema: Zoi.object(%{case_id: Zoi.string()})
  def run(%{case_id: id}, context), do: {:ok, %{context.agent_state | case_id: id}}
end
