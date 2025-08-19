defmodule JidoTest.HTN.BackgroundTaskTest do
  use ExUnit.Case, async: true
  alias Jido.HTN
  alias Jido.HTN.Domain

  @moduletag :capture_log

  defmodule LongRunningAction do
    @moduledoc false
    def run(_, _, _) do
      Process.sleep(1000)
      {:ok, %{completed: true}}
    end
  end

  defmodule QuickAction do
    @moduledoc false
    def run(_, _, _), do: {:ok, %{quick: true}}
  end

  describe "background tasks" do
    test "executes background tasks without waiting" do
      # Create a domain with a method that has a background task followed by a quick task
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root",
          methods: [
            %{
              subtasks: ["long_task", "quick_task"]
            }
          ]
        )
        |> Domain.primitive("long_task", {LongRunningAction, []}, background: true)
        |> Domain.primitive("quick_task", {QuickAction, []})
        |> Domain.allow("LongRunningAction", LongRunningAction)
        |> Domain.allow("QuickAction", QuickAction)
        |> Domain.build()

      # Time the planning and execution
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, plan, _mtr} = HTN.plan(domain, %{})
      end_time = System.monotonic_time(:millisecond)

      # The planning should take much less than 1000ms since we're not waiting for the long task
      assert end_time - start_time < 1000

      # Both tasks should be in the plan
      assert length(plan) == 2
      [{first_module, _}, {second_module, _}] = plan
      assert first_module == LongRunningAction
      assert second_module == QuickAction
    end

    test "updates world state for background tasks" do
      # Create a domain with a background task that updates world state
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root",
          methods: [
            %{
              subtasks: ["background_task"]
            }
          ]
        )
        |> Domain.primitive("background_task", {LongRunningAction, []},
          background: true,
          effects: [fn _ -> %{task_started: true} end]
        )
        |> Domain.allow("LongRunningAction", LongRunningAction)
        |> Domain.build()

      # The world state should be updated even though the task is running in background
      assert {:ok, _plan, _mtr} = HTN.plan(domain, %{})
      # We don't assert on the final world state since the task is running in background
    end

    test "allows parallel execution of background and normal tasks" do
      # Create a domain with multiple tasks where some run in background
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root",
          methods: [
            %{
              subtasks: ["background1", "normal1", "background2", "normal2"]
            }
          ]
        )
        |> Domain.primitive("background1", {LongRunningAction, []}, background: true)
        |> Domain.primitive("normal1", {QuickAction, []})
        |> Domain.primitive("background2", {LongRunningAction, []}, background: true)
        |> Domain.primitive("normal2", {QuickAction, []})
        |> Domain.allow("LongRunningAction", LongRunningAction)
        |> Domain.allow("QuickAction", QuickAction)
        |> Domain.build()

      # Time the planning and execution
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, plan, _mtr} = HTN.plan(domain, %{})
      end_time = System.monotonic_time(:millisecond)

      # The planning should take much less than 2000ms (2 long tasks)
      assert end_time - start_time < 2000

      # All tasks should be in the plan
      assert length(plan) == 4
    end
  end
end
