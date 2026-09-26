defmodule JidoAI.Examples.Completion.Receipts do
  @moduledoc "Count committed receipts in Plugin-owned state."
  use Jido.Plugin, agent: __MODULE__.Agent, agent_server: __MODULE__.AgentServer

  defmodule Agent do
    @moduledoc false
    use Jido.Agent.Plugin
    alias JidoAI.Examples.Completion.Receipt
    def state_spec(_), do: {:receipt_count, Zoi.integer() |> Zoi.default(0)}
    def directives(_), do: [Receipt]

    def reduce(reduction, _),
      do: {:ok, reduction.plugin_state + Enum.count(reduction.directives, &is_struct(&1, Receipt))}
  end

  defmodule AgentServer do
    @moduledoc false
    use Jido.AgentServer.Plugin
    def dispatch(nil, _receipt, _context, _opts), do: :ok
  end
end
