defmodule JidoAI.Examples.Completion.Receipts do
  @moduledoc "Count committed receipts in Plugin-owned state."
  use Jido.Plugin
  alias JidoAI.Examples.Completion.Receipt

  def state_spec(_), do: {:receipt_count, Zoi.integer() |> Zoi.default(0)}
  def directives(_), do: [Receipt]
  def validate_directive(%Receipt{entry: entry} = receipt, _) when is_binary(entry) and entry != "", do: {:ok, receipt}
  def validate_directive(_, _), do: {:error, :invalid_receipt}
  def update_state(count, receipts, _), do: {:ok, count + length(receipts)}
  def dispatch(nil, _receipt, _context, _opts), do: :ok
end
