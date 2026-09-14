defmodule JidoAI.Examples.CallCounts.Input do
  @behaviour Jido.AI.Control
  def check(_, %{reject_at: :input}), do: {:error, :input_rejected}

  def check(_, %{hold_input: true, observer: observer}) do
    send(observer, {:input_held, self()})

    receive do
      :release -> :ok
    end
  end

  def check(_, _), do: :ok
end

defmodule JidoAI.Examples.CallCounts.Model do
  @behaviour Jido.AI.Control
  def check(_, %{reject_at: :model}), do: {:error, :model_rejected}
  def check(_, _), do: :ok
end

defmodule JidoAI.Examples.CallCounts.Echo do
  use Jido.Action,
    name: "scope_echo",
    schema: Zoi.object(%{value: Zoi.integer()})

  def run(%{value: value}, _context), do: {:ok, %{value: value}}
end

defmodule JidoAI.Examples.CallCounts.Agent do
  use Jido.Agent, name: "call_counts", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      controls do
        input(JidoAI.Examples.CallCounts.Input)
        model(JidoAI.Examples.CallCounts.Model)
      end

      requests do
        mode(:session)
        streaming(false)
      end

      tools do
        action JidoAI.Examples.CallCounts.Echo, as: :scope_echo
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "case.review", ai(:assistant)
  end
end
