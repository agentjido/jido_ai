defmodule JidoAI.Examples.Completion.Apply do
  @moduledoc false
  defstruct [:mode, :observer]
end

defmodule JidoAI.Examples.Completion.Ledger do
  @moduledoc "A real Plugin can reject final reduction or fail after commit."
  use Jido.Plugin
  alias JidoAI.Examples.Completion.Apply

  def state_spec(_),
    do: {:ledger, Zoi.object(%{value: Zoi.string() |> Zoi.default("")}) |> Zoi.default(%{value: ""})}

  def directives(_), do: [Apply]
  def validate_directive(%Apply{} = directive, _), do: {:ok, directive}

  def prepare(command, opts) do
    if opts[:deny_settle] == true and command.signal.type == Jido.AI.Orchestration.settle_type(),
      do: {:error, :fixture_settlement_denied},
      else: {:ok, command}
  end

  def update_state(state, [], _), do: {:ok, state}

  def update_state(state, directives, _) do
    Enum.each(directives, &send(&1.observer, {:ledger_reduce, &1.mode}))

    cond do
      Enum.any?(directives, &(&1.mode == "reject")) ->
        {:error, :fixture_reducer_rejected}

      Enum.any?(directives, &(&1.mode == "inflate")) ->
        {:ok, %{value: String.duplicate("x", 20_000)}}

      true ->
        {:ok, state}
    end
  end

  def dispatch(nil, directive, _, _) do
    send(directive.observer, {:ledger_dispatch, directive.mode})
    if directive.mode == "dispatch_fail", do: {:error, :fixture_dispatch_failed}, else: :ok
  end
end

defmodule JidoAI.Examples.Completion.Tool do
  @moduledoc false
  use Jido.Action, name: "ledger_tool", schema: Zoi.object(%{mode: Zoi.string()})

  def run(%{mode: mode}, context) do
    send(context.observer, {:ledger_tool, mode})
    modes = if mode == "dispatch_fail", do: [mode, "after_failure"], else: [mode]

    {:ok, %{mode: mode}, Enum.map(modes, &%JidoAI.Examples.Completion.Apply{mode: &1, observer: context.observer})}
  end
end

defmodule JidoAI.Examples.Completion.Fill do
  @moduledoc false
  use Jido.Action, name: "fill_state", schema: Zoi.object(%{bytes: Zoi.integer() |> Zoi.min(0)})

  def run(%{bytes: bytes}, context),
    do: {:ok, %{context.agent_state | reply: String.duplicate(".", bytes)}}
end

defmodule JidoAI.Examples.Completion.FixtureAgent do
  @moduledoc "Completion commits use core Plugin and state validation."
  use Jido.Agent, name: "completion_example", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})
    plugin JidoAI.Examples.Completion.Ledger

    ai :assistant do
      effect_policy(%{allow: [JidoAI.Examples.Completion.Apply]})

      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
        effect_policy(%{mode: :allow_all})
      end

      tools do
        action JidoAI.Examples.Completion.Tool, as: :ledger_tool, forward_context: [:observer]
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
    route "fill", JidoAI.Examples.Completion.Fill
  end
end
