defmodule JidoTest.Exec.ChainTest do
  use JidoTest.ActionCase, async: false

  import ExUnit.CaptureLog

  alias Jido.Exec.Chain
  alias JidoTest.TestActions.Add
  alias JidoTest.TestActions.ContextAwareMultiply
  alias JidoTest.TestActions.ErrorAction
  alias JidoTest.TestActions.Multiply
  alias JidoTest.TestActions.Square
  alias JidoTest.TestActions.Subtract
  alias JidoTest.TestActions.WriteFile

  describe "chain/3" do
    test "executes a simple chain of actions successfully" do
      capture_log(fn ->
        result = Chain.chain([Add, Multiply], %{value: 5, amount: 2})
        assert {:ok, %{value: 14, amount: 2}} = result
      end)
    end

    test "supports new syntax with action options" do
      capture_log(fn ->
        result =
          Chain.chain(
            [
              Add,
              {WriteFile, [file_name: "test.txt", content: "Hello"]},
              Multiply
            ],
            %{value: 1, amount: 2}
          )

        assert {:ok, %{value: 6, written_file: "test.txt"}} = result
      end)
    end

    test "executes a chain with mixed action formats" do
      capture_log(fn ->
        result = Chain.chain([Add, {Multiply, [amount: 3]}, Subtract], %{value: 5})
        assert {:ok, %{value: 15, amount: 3}} = result
      end)
    end

    test "executes a chain with map action parameters" do
      capture_log(fn ->
        result = Chain.chain([Add, {Multiply, %{amount: 3}}, Subtract], %{value: 5})
        assert {:ok, %{value: 15, amount: 3}} = result
      end)
    end

    test "handles string keys in action parameters" do
      capture_log(fn ->
        result = Chain.chain([Add, {Multiply, %{"amount" => 3}}, Subtract], %{value: 5})
        assert {:error, %Jido.Action.Error.InvalidInputError{}} = result
      end)
    end

    test "handles empty map action parameters" do
      capture_log(fn ->
        result = Chain.chain([Add, {Multiply, %{}}, Subtract], %{value: 5, amount: 2})
        assert {:ok, %{value: 12, amount: 2}} = result
      end)
    end

    test "handles nil action parameters" do
      capture_log(fn ->
        result = Chain.chain([Add, {Multiply, nil}, Subtract], %{value: 5})

        assert {:error, error} = result
        assert is_exception(error)
        assert Exception.message(error) =~ "Invalid chain action"
      end)
    end

    test "handles errors in the chain" do
      capture_log(fn ->
        result = Chain.chain([Add, ErrorAction, Multiply], %{value: 5, error_type: :runtime})
        assert {:error, error} = result
        assert is_exception(error)
        assert Exception.message(error) =~ "Runtime error"
      end)
    end

    test "stops execution on first error" do
      capture_log(fn ->
        result = Chain.chain([Add, ErrorAction, Multiply], %{value: 5, error_type: :runtime})
        assert {:error, %_{}} = result
        assert is_exception(result |> elem(1))
        refute match?({:ok, %{value: _}}, result)
      end)
    end

    test "handles invalid actions in the chain" do
      capture_log(fn ->
        result = Chain.chain([Add, :invalid_action, Multiply], %{value: 5})

        assert {:error, error} = result
        assert is_exception(error)
        assert Exception.message(error) =~ "Failed to compile module :invalid_action: :nofile"
      end)
    end

    test "executes chain asynchronously" do
      capture_log(fn ->
        task = Chain.chain([Add, Multiply], %{value: 5}, async: true)
        assert %Task{} = task
        assert {:ok, %{value: 12}} = Task.await(task)
      end)
    end

    test "passes context to actions" do
      capture_log(fn ->
        context = %{multiplier: 3}
        result = Chain.chain([Add, ContextAwareMultiply], %{value: 5}, context: context)
        assert {:ok, %{value: 18}} = result
      end)
    end

    test "logs debug messages for each action" do
      log =
        capture_log(fn ->
          Chain.chain([Add, Multiply], %{value: 5}, timeout: 10)
        end)

      # assert log =~ "Executing action in chain"
      assert log =~ "Executing JidoTest.TestActions.Add with params"
      assert log =~ "Executing JidoTest.TestActions.Multiply with params"
    end

    test "logs warnings for failed actions" do
      log =
        capture_log(fn ->
          Chain.chain([Add, ErrorAction], %{value: 5, error_type: :runtime, timeout: 10})
        end)

      assert log =~ "Exec in chain failed"
      assert log =~ "Action JidoTest.TestActions.ErrorAction failed"
    end

    test "executes a complex chain of actions" do
      capture_log(fn ->
        result =
          Chain.chain(
            [
              Add,
              {Multiply, [amount: 3]},
              Subtract,
              {Square, [amount: 2]}
            ],
            %{value: 10}
          )

        assert {:ok, %{value: 900}} = result
      end)
    end
  end
end
