defmodule JidoAI.Examples.Completion.RecordReceipt do
  @moduledoc "Return a portable receipt effect for the Agent's owning Plugin."
  use Jido.Action, name: "record_receipt", schema: Zoi.object(%{entry: Zoi.string() |> Zoi.min(1)})

  def run(%{entry: entry}, _context),
    do: {:ok, %{entry: entry}, [%JidoAI.Examples.Completion.Receipt{entry: entry}]}
end
