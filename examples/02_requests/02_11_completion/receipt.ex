defmodule JidoAI.Examples.Completion.Receipt do
  @moduledoc "A portable record of one completed receipt operation."
  @behaviour Jido.Agent.Directive
  defstruct [:entry]

  @impl true
  def validate(%__MODULE__{entry: entry} = receipt) when is_binary(entry) and entry != "", do: {:ok, receipt}
  def validate(_), do: {:error, :invalid_receipt}
end
