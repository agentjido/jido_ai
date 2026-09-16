defmodule Jido.AI.Tools.ExecutorBoundaryTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Tools.Executor

  defmodule Propose do
    use Jido.Action, name: "propose", schema: Zoi.object(%{value: Zoi.integer()})

    def run(%{value: value}, _context),
      do: {:ok, Jido.Action.Output.raw(value), [Jido.AI.Effects.state(%{value: value})]}
  end

  test "the shared target boundary leaves effects for its owning policy layer" do
    call = %{id: "one", name: "propose"}
    context = %{effect_policy: %{mode: :deny_all}}

    assert {:ok, 7, [%Jido.AI.Effects.State{state: %{value: 7}}]} =
             Executor.execute_target(Propose, %{value: 7}, context, [timeout: 1000], call)

    assert {:ok, 7, []} = Executor.execute_module(Propose, %{value: 7}, context)
  end

  test "both entry points preserve core validation failures as normalized tool errors" do
    assert {:error, shared, []} =
             Executor.execute_target(Propose, %{}, %{}, [timeout: 1000], %{id: "one", name: "propose"})

    assert {:error, direct, []} = Executor.execute_module(Propose, %{}, %{})
    assert shared.type == direct.type
    assert is_binary(shared.message)
    assert is_binary(direct.message)
  end

  test "Turn exposes values and projections, not execution" do
    Code.ensure_loaded!(Jido.AI.Model.Response)

    for {name, arity} <- [execute: 4, execute_module: 4, run_tools: 3, run_tool_calls: 3] do
      refute function_exported?(Jido.AI.Model.Response, name, arity)
    end
  end
end
