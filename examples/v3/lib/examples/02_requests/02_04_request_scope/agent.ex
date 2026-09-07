defmodule JidoAI.Examples.RequestScope.Echo do
  @moduledoc "Returns the validated tool input."
  use Jido.Action, name: "scope_echo", schema: Zoi.object(%{value: Zoi.integer()})
  def run(params, _), do: {:ok, params}
end

defmodule JidoAI.Examples.RequestScope.Open do
  @moduledoc "A tool with an explicitly open nested object."
  use Jido.Action,
    name: "scope_open",
    schema:
      Zoi.object(
        %{
          params: Zoi.object(%{}, unrecognized_keys: :preserve)
        },
        unrecognized_keys: :error
      )

  def run(params, _), do: {:ok, params}
end

defmodule JidoAI.Examples.RequestScope.Agent do
  @moduledoc "One default model turn; each request can select its own tools and output."
  use Jido.AI.Agent,
    name: "scope_agent",
    model: :example,
    tools: [JidoAI.Examples.RequestScope.Echo],
    streaming: false,
    max_iterations: 1
end

defmodule JidoAI.Examples.RequestScope.TwoTurns do
  @moduledoc "A two-turn policy for checking smaller request limits."
  use Jido.AI.Agent,
    name: "two_turn_scope_agent",
    model: :example,
    tools: [JidoAI.Examples.RequestScope.Echo],
    streaming: false,
    max_iterations: 2
end
