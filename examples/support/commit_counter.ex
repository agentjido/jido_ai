defmodule JidoAI.Examples.Support.CommitCounter do
  @moduledoc "An ordinary Plugin that counts successful commits."
  use Jido.Plugin, agent: __MODULE__.Agent

  defmodule Agent do
    @moduledoc false
    use Jido.Agent.Plugin
    def state_spec(_), do: {:commits, Zoi.integer() |> Zoi.default(0)}
    def reduce(reduction, _), do: {:ok, reduction.plugin_state + 1}
  end
end
