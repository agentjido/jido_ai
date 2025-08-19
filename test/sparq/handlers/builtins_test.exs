defmodule Sparq.Handlers.BuiltinsTest do
  use ExUnit.Case, async: true
  alias Sparq.{Context, Handlers.Builtins}

  describe "handle/4" do
    setup do
      ctx = Context.new()
      {:ok, ctx: ctx}
    end

    test "handles addition", %{ctx: ctx} do
      {result, _ctx} = Builtins.handle(:+, %{}, [2, 3], ctx)
      assert result == 5
    end

    test "handles subtraction", %{ctx: ctx} do
      {result, _ctx} = Builtins.handle(:-, %{}, [5, 3], ctx)
      assert result == 2
    end

    test "handles multiplication", %{ctx: ctx} do
      {result, _ctx} = Builtins.handle(:*, %{}, [4, 3], ctx)
      assert result == 12
    end

    test "handles division", %{ctx: ctx} do
      {result, _ctx} = Builtins.handle(:/, %{}, [6, 2], ctx)
      assert result == 3.0
    end

    test "handles floating point arithmetic", %{ctx: ctx} do
      {result, _ctx} = Builtins.handle(:+, %{}, [2.5, 3.7], ctx)
      assert_in_delta result, 6.2, 0.0001

      {result, _ctx} = Builtins.handle(:-, %{}, [5.5, 3.2], ctx)
      assert_in_delta result, 2.3, 0.0001

      {result, _ctx} = Builtins.handle(:*, %{}, [4.2, 3.0], ctx)
      assert_in_delta result, 12.6, 0.0001

      {result, _ctx} = Builtins.handle(:/, %{}, [6.4, 2.0], ctx)
      assert_in_delta result, 3.2, 0.0001
    end

    test "handles mixed integer and float arithmetic", %{ctx: ctx} do
      {result, _ctx} = Builtins.handle(:+, %{}, [2, 3.7], ctx)
      assert_in_delta result, 5.7, 0.0001

      {result, _ctx} = Builtins.handle(:-, %{}, [5.5, 3], ctx)
      assert_in_delta result, 2.5, 0.0001

      {result, _ctx} = Builtins.handle(:*, %{}, [4, 3.5], ctx)
      assert_in_delta result, 14.0, 0.0001

      {result, _ctx} = Builtins.handle(:/, %{}, [6, 2.0], ctx)
      assert_in_delta result, 3.0, 0.0001
    end

    test "raises on division by zero", %{ctx: ctx} do
      assert_raise ArithmeticError, "division by zero", fn ->
        Builtins.handle(:/, %{}, [1, 0], ctx)
      end

      assert_raise ArithmeticError, "division by zero", fn ->
        Builtins.handle(:/, %{}, [1.0, 0], ctx)
      end

      assert_raise ArithmeticError, "division by zero", fn ->
        Builtins.handle(:/, %{}, [1, 0.0], ctx)
      end
    end

    test "raises on unknown operation", %{ctx: ctx} do
      assert_raise ArgumentError, "Unknown builtin operation: :unknown", fn ->
        Builtins.handle(:unknown, %{}, [1, 2], ctx)
      end
    end
  end

  describe "validate/2" do
    test "validates division by zero" do
      assert {:error, :division_by_zero} = Builtins.validate(:/, [1, 0])
      assert {:error, :division_by_zero} = Builtins.validate(:/, [1.0, 0])
      assert {:error, :division_by_zero} = Builtins.validate(:/, [1, 0.0])
    end

    test "validates arity" do
      assert {:error, :invalid_arity} = Builtins.validate(:+, [1])
      assert {:error, :invalid_arity} = Builtins.validate(:+, [1, 2, 3])
      assert {:error, :invalid_arity} = Builtins.validate(:-, [])
      assert {:error, :invalid_arity} = Builtins.validate(:*, [1])
      assert {:error, :invalid_arity} = Builtins.validate(:/, [1])
    end

    test "validates numeric types" do
      assert {:error, :invalid_type} = Builtins.validate(:+, ["1", 2])
      assert {:error, :invalid_type} = Builtins.validate(:+, [1, "2"])
      assert {:error, :invalid_type} = Builtins.validate(:+, [:one, :two])
      assert {:error, :invalid_type} = Builtins.validate(:+, [[], 2])
      assert {:error, :invalid_type} = Builtins.validate(:+, [1, %{}])
      assert {:error, :invalid_type} = Builtins.validate(:+, [nil, 2])
      assert {:error, :invalid_type} = Builtins.validate(:+, [1, nil])
    end

    test "validates valid operations" do
      assert :ok = Builtins.validate(:+, [1, 2])
      assert :ok = Builtins.validate(:-, [1, 2])
      assert :ok = Builtins.validate(:*, [1, 2])
      assert :ok = Builtins.validate(:/, [1, 2])
      assert :ok = Builtins.validate(:+, [1.0, 2.0])
      assert :ok = Builtins.validate(:-, [1, 2.0])
      assert :ok = Builtins.validate(:*, [1.0, 2])
      assert :ok = Builtins.validate(:/, [1, 2.0])
    end
  end
end
