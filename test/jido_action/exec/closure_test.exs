defmodule JidoTest.Exec.ClosureTest do
  use JidoTest.ActionCase, async: false

  import ExUnit.CaptureLog
  import Mimic

  alias Jido.Exec
  alias Jido.Exec.Closure
  alias JidoTest.TestActions.BasicAction
  alias JidoTest.TestActions.ContextAction
  alias JidoTest.TestActions.ErrorAction

  setup :set_mimic_global

  describe "closure/3" do
    test "creates a closure that can be called with params" do
      capture_log(fn ->
        closure = Closure.closure(BasicAction, %{})
        assert is_function(closure, 1)

        result = closure.(%{value: 5})
        assert {:ok, %{value: 5}} = result
      end)
    end

    test "closure preserves context and options" do
      expect(Exec, :run, fn _, _, _, _ -> {:ok, %{mocked: true}} end)

      closure = Closure.closure(ContextAction, %{context_key: "value"}, timeout: 5000)
      closure.(%{input: "test"})

      verify!(Exec)
    end

    test "closure handles errors from the action" do
      capture_log(fn ->
        closure = Closure.closure(ErrorAction)

        assert {:error, error} = closure.(%{error_type: :runtime})
        assert is_exception(error)
        assert Exception.message(error) =~ "Runtime error"
      end)
    end

    test "closure validates params before execution" do
      # capture_log(fn ->
      closure = Closure.closure(BasicAction, %{})
      assert {:error, %Jido.Action.Error.InvalidInputError{}} = closure.(%{invalid: "params"})
      # end)
    end
  end

  describe "async_closure/3" do
    test "creates an async closure that returns an async_ref" do
      capture_log(fn ->
        async_closure = Closure.async_closure(BasicAction)
        assert is_function(async_closure, 1)

        async_ref = async_closure.(%{value: 10})
        assert is_map(async_ref)
        assert is_pid(async_ref.pid)
        assert is_reference(async_ref.ref)

        assert {:ok, %{value: 10}} = Exec.await(async_ref)
      end)
    end

    test "async_closure preserves context and options" do
      capture_log(fn ->
        expect(Exec, :run_async, fn _, _, _, _ -> %{ref: make_ref(), pid: self()} end)

        async_closure =
          Closure.async_closure(ContextAction, %{async_context: true}, timeout: 10_000)

        async_closure.(%{input: "async_test"})

        verify!(Exec)
      end)
    end

    test "async_closure handles errors from the action" do
      capture_log(fn ->
        async_closure = Closure.async_closure(ErrorAction)
        async_ref = async_closure.(%{error_type: :runtime})

        assert {:error, error} = Exec.await(async_ref)
        assert is_exception(error)
        assert Exception.message(error) =~ "Runtime error"
      end)
    end
  end

  describe "error handling and edge cases" do
    test "closure handles invalid action" do
      assert_raise FunctionClauseError, fn ->
        Closure.closure("not_a_module")
      end
    end

    test "async_closure handles invalid action" do
      assert_raise FunctionClauseError, fn ->
        Closure.async_closure("not_a_module")
      end
    end

    test "closure with empty context and opts" do
      closure = Closure.closure(BasicAction)
      assert {:error, %Jido.Action.Error.InvalidInputError{}} = closure.(%{})
    end

    test "async_closure with empty context and opts" do
      async_closure = Closure.async_closure(BasicAction)
      async_ref = async_closure.(%{})
      assert {:error, %Jido.Action.Error.InvalidInputError{}} = Exec.await(async_ref)
    end
  end
end
