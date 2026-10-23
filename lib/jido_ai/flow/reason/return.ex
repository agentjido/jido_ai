defmodule Jido.AI.Flow.Reason.Return do
  @moduledoc false

  use Jido.Action,
    name: "jido_ai_reason_return",
    description: "Return one validated AI reasoning result"

  @impl Jido.Action
  def run(%{result: %{output: _output, usage: usage, trace: trace} = result}, _context)
      when is_map(usage) and is_list(trace),
      do: {:ok, result}

  def run(%{result: result}, _context), do: {:error, {:invalid_reasoning_result, result}}
end
