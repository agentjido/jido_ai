defmodule JidoTest.Exec.ChainInterruptTest do
  use JidoTest.ActionCase, async: true

  import ExUnit.CaptureLog

  alias Jido.Exec.Chain
  alias JidoTest.TestActions.Add
  alias JidoTest.TestActions.Multiply
  alias JidoTest.TestActions.SlowExec

  @moduletag :capture_log

  describe "chain/3 with interrupt" do
    test "interrupts chain after first action" do
      actions = [Add, SlowExec, Multiply]
      initial_params = %{value: 5, amount: 2}

      # Interrupt after first action
      interrupt_after_first = fn ->
        count = Process.get(:action_count, 0)
        Process.put(:action_count, count + 1)
        count >= 1
      end

      result = Chain.chain(actions, initial_params, interrupt_check: interrupt_after_first)

      assert {:interrupted, partial_result} = result
      # Add action completed
      assert partial_result.value == 7
      refute Map.has_key?(partial_result, :slow_action_complete)
    end

    test "completes chain when interrupt check returns false" do
      actions = [Add, Multiply]
      initial_params = %{value: 5, amount: 2}

      result = Chain.chain(actions, initial_params, interrupt_check: fn -> false end)

      assert {:ok, final_result} = result
      # Both actions completed
      assert final_result.value == 14
    end

    test "interrupts immediately if interrupt check starts true" do
      actions = [Add, Multiply]
      initial_params = %{value: 5, amount: 2}

      result = Chain.chain(actions, initial_params, interrupt_check: fn -> true end)

      assert {:interrupted, partial_result} = result
      # No actions completed
      assert partial_result == initial_params
    end

    test "logs interrupt event" do
      actions = [Add, SlowExec]
      initial_params = %{value: 5, amount: 2}

      log =
        capture_log([level: :info], fn ->
          Chain.chain(actions, initial_params, interrupt_check: fn -> true end)
        end)

      assert log =~ "Chain interrupted before action"
    end

    test "handles async execution with interruption" do
      actions = [
        JidoTest.TestActions.Add,
        JidoTest.TestActions.DelayAction,
        JidoTest.TestActions.Multiply
      ]

      initial_params = %{value: 5, amount: 2, delay: 100}

      # Use an Agent to control interruption timing
      {:ok, interrupt_agent} = Agent.start_link(fn -> false end)

      interrupt_check = fn -> Agent.get(interrupt_agent, & &1) end

      task =
        Chain.chain(actions, initial_params,
          async: true,
          interrupt_check: interrupt_check
        )

      # Allow first action to complete
      Process.sleep(50)
      Agent.update(interrupt_agent, fn _ -> true end)

      result = Task.await(task)
      Agent.stop(interrupt_agent)

      assert {:interrupted, partial_result} = result
      # Add action completed
      assert partial_result.value == 7
    end

    test "preserves error handling when interrupted" do
      actions = [
        JidoTest.TestActions.BasicAction,
        JidoTest.TestActions.ErrorAction,
        JidoTest.TestActions.BasicAction
      ]

      initial_params = %{value: 5, error_type: :validation}

      log =
        capture_log([level: :warning], fn ->
          result = Chain.chain(actions, initial_params, interrupt_check: fn -> false end)
          assert {:error, error} = result
          assert is_exception(error)
          assert error.__struct__ == Jido.Action.Error.ExecutionFailureError
          assert Exception.message(error) =~ "Validation error"
        end)

      assert log =~ "Exec in chain failed"
    end

    test "handles empty action list with interrupt check" do
      result = Chain.chain([], %{value: 5}, interrupt_check: fn -> true end)
      assert {:ok, %{value: 5}} = result
    end
  end
end
