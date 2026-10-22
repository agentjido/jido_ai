defmodule JidoAI.Examples.TraceAndCycles.Check do
  @moduledoc "Return a checksum of the complete tool input, independently of event redaction."
  use Jido.Action,
    name: "check",
    description: "Check a supplied payload",
    schema: Zoi.object(%{payload: Zoi.map()})

  def run(%{payload: payload}, _context) do
    fingerprint =
      :crypto.hash(:sha256, :erlang.term_to_binary(payload, [:deterministic])) |> Base.encode16(case: :lower)

    {:ok, %{checked: true, fingerprint: fingerprint}}
  end
end
