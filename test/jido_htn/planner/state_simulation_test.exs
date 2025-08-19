defmodule JidoTest.HTN.Planner.StateSimulationTest do
  use ExUnit.Case, async: true
  alias Jido.HTN
  alias Jido.HTN.Domain

  @moduletag :capture_log

  defmodule TaskA do
    @moduledoc false
    def run(_params, _world_state, _context), do: {:ok, %{}}
  end

  defmodule TaskB do
    @moduledoc false
    def run(_params, _world_state, _context), do: {:ok, %{}}
  end

  defmodule TaskC do
    @moduledoc false
    def run(_params, _world_state, _context), do: {:ok, %{}}
  end

  describe "state simulation during planning" do
    test "enables planning with dependent tasks" do
      # Define a test domain with sequential tasks where B depends on A's effects
      {:ok, domain} =
        "State Simulation Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["DoAandB"]}])
        |> Domain.compound("DoAandB", methods: [%{subtasks: ["A", "B"]}])
        |> Domain.primitive("A", {TaskA, []},
          preconditions: [],
          effects: [fn _result -> %{B_unlocked: true, A_done: true} end]
        )
        |> Domain.primitive("B", {TaskB, []},
          preconditions: [fn state -> Map.get(state, :B_unlocked) == true end],
          effects: [fn _result -> %{B_done: true} end]
        )
        |> Domain.allow("TaskA", TaskA)
        |> Domain.allow("TaskB", TaskB)
        |> Domain.build()

      # Initial state: A can be done, but B is locked
      initial_state = %{
        can_do_A: true,
        B_unlocked: false,
        A_done: false,
        B_done: false
      }

      # Without state simulation, this would fail because when checking B's
      # preconditions, B_unlocked would still be false
      # With state simulation, A's effects make B_unlocked true, allowing B to be planned
      assert {:ok, [{TaskA, []}, {TaskB, []}], _mtr} = HTN.plan(domain, initial_state)
    end

    test "enables multi-step state propagation A -> B -> C" do
      {:ok, domain} =
        "State Simulation Multi-step Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["DoABC"]}])
        |> Domain.compound("DoABC", methods: [%{subtasks: ["A", "B", "C"]}])
        |> Domain.primitive("A", {TaskA, []},
          preconditions: [],
          effects: [fn _result -> %{B_unlocked: true, A_done: true} end]
        )
        |> Domain.primitive("B", {TaskB, []},
          preconditions: [fn state -> Map.get(state, :B_unlocked) == true end],
          effects: [fn _result -> %{C_unlocked: true, B_done: true} end]
        )
        |> Domain.primitive("C", {TaskC, []},
          preconditions: [fn state -> Map.get(state, :C_unlocked) == true end],
          effects: [fn _result -> %{C_done: true} end]
        )
        |> Domain.allow("TaskA", TaskA)
        |> Domain.allow("TaskB", TaskB)
        |> Domain.allow("TaskC", TaskC)
        |> Domain.build()

      initial_state = %{
        B_unlocked: false,
        C_unlocked: false,
        A_done: false,
        B_done: false,
        C_done: false
      }

      # This should succeed with state simulation - A enables B, which enables C
      assert {:ok, [{TaskA, []}, {TaskB, []}, {TaskC, []}], _mtr} =
               HTN.plan(domain, initial_state)
    end

    test "properly handles background tasks with state simulation" do
      {:ok, domain} =
        "Background Tasks State Simulation Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["DoAB"]}])
        |> Domain.compound("DoAB", methods: [%{subtasks: ["A", "B"]}])
        |> Domain.primitive("A", {TaskA, []},
          background: true,
          preconditions: [],
          effects: [fn _result -> %{B_unlocked: true} end]
        )
        |> Domain.primitive("B", {TaskB, []},
          preconditions: [fn state -> Map.get(state, :B_unlocked) == true end],
          effects: [fn _result -> %{B_done: true} end]
        )
        |> Domain.allow("TaskA", TaskA)
        |> Domain.allow("TaskB", TaskB)
        |> Domain.build()

      initial_state = %{
        B_unlocked: false,
        B_done: false
      }

      # This should succeed with A's effects enabling B,
      # even though A is a background task
      assert {:ok, [{TaskA, []}, {TaskB, []}], _mtr} = HTN.plan(domain, initial_state)
    end

    test "correctly rejects plans when a task disables a precondition for a later task" do
      {:ok, domain} =
        "Disabling Effects Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["DoABInvalid"]}])
        |> Domain.compound("DoABInvalid", methods: [%{subtasks: ["A", "B"]}])
        |> Domain.primitive("A", {TaskA, []},
          preconditions: [],
          effects: [fn _result -> %{A_done: true, B_unlocked: false} end]
        )
        |> Domain.primitive("B", {TaskB, []},
          preconditions: [fn state -> Map.get(state, :B_unlocked) == true end],
          effects: [fn _result -> %{B_done: true} end]
        )
        |> Domain.allow("TaskA", TaskA)
        |> Domain.allow("TaskB", TaskB)
        |> Domain.build()

      initial_state = %{
        # B is initially unlocked
        B_unlocked: true,
        A_done: false,
        B_done: false
      }

      # This should fail because A's effects disable B's precondition
      assert {:error, _} = HTN.plan(domain, initial_state)
    end
  end
end
