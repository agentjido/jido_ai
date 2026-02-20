defmodule Jido.AI.Reasoning.AlgorithmOfThoughts.Result do
  @moduledoc """
  Canonical structured result contract for Algorithm-of-Thoughts (AoT) runs.
  """

  alias Jido.AI.Reasoning.AlgorithmOfThoughts.Machine

  @type termination :: %{
          reason: atom(),
          status: Machine.external_status() | atom(),
          duration_ms: non_neg_integer()
        }

  @type t :: %{
          answer: String.t() | nil,
          found_solution?: boolean(),
          first_operations_considered: non_neg_integer(),
          backtracking_steps: non_neg_integer(),
          raw_response: String.t(),
          usage: map(),
          termination: termination(),
          diagnostics: map()
        }

  @doc """
  Builds an AoT result payload from parsed data and machine state.
  """
  @spec build(Machine.t(), map(), atom(), Machine.external_status(), String.t()) :: t()
  def build(%Machine{} = machine, parsed, reason, status, raw_response) do
    %{
      answer: Map.get(parsed, :answer),
      found_solution?: Map.get(parsed, :found_solution?, false),
      first_operations_considered: Map.get(parsed, :first_operations_considered, 0),
      backtracking_steps: Map.get(parsed, :backtracking_steps, 0),
      raw_response: raw_response || "",
      usage: machine.usage || %{},
      termination: %{
        reason: reason,
        status: status,
        duration_ms: duration_ms(machine)
      },
      diagnostics: Map.get(parsed, :diagnostics, %{})
    }
  end

  defp duration_ms(%Machine{started_at: nil}), do: 0
  defp duration_ms(%Machine{started_at: started_at}), do: System.monotonic_time(:millisecond) - started_at
end
