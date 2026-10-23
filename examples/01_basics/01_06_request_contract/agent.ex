defmodule JidoAI.Examples.RequestContract.Lookup do
  @moduledoc "Looks up one value for the request-contract example."

  use Jido.Action,
    name: "request_contract_lookup",
    description: "Look up one named value",
    schema: Zoi.object(%{name: Zoi.string()})

  @impl Jido.Action
  def run(%{name: name}, _context), do: {:ok, %{name: name, value: "known"}}
end

defmodule JidoAI.Examples.RequestContract.Calculate do
  @moduledoc "Adds two integers for the request-contract example."

  use Jido.Action,
    name: "request_contract_calculate",
    description: "Add two integers",
    schema: Zoi.object(%{left: Zoi.integer(), right: Zoi.integer()})

  @impl Jido.Action
  def run(%{left: left, right: right}, _context), do: {:ok, %{sum: left + right}}
end

defmodule JidoAI.Examples.RequestContract.Agent do
  @moduledoc "Shows request preparation, tool visibility, results, and events."

  use Jido.AI.Agent, name: "request_contract_example"

  ai do
    model :fast
    instructions "Answer in one short sentence."

    tools do
      action JidoAI.Examples.RequestContract.Lookup, as: :lookup
      action JidoAI.Examples.RequestContract.Calculate, as: :calculate
    end

    controls do
      timeout 10_000
      max_iterations 2
      max_model_calls 3
      max_tool_calls 2
    end
  end
end
