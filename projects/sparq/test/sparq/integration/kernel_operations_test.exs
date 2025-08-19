defmodule Sparq.Integration.KernelOperationsTest do
  use SparqTest.ASTCase

  describe "type checks" do
    test "is_tuple" do
      ast = {:is_tuple, [], [{:tuple, [], [1, 2]}]}
      assert_eval(ast, true)

      ast = {:is_tuple, [], [[1, 2]]}
      assert_eval(ast, false)
    end

    test "is_list" do
      ast = {:is_list, [], [[1, 2]]}
      assert_eval(ast, true)

      ast = {:is_list, [], [{:tuple, [], [1, 2]}]}
      assert_eval(ast, false)
    end

    test "is_number" do
      ast = {:is_number, [], [42]}
      assert_eval(ast, true)

      ast = {:is_number, [], ["42"]}
      assert_eval(ast, false)
    end

    test "is_atom" do
      ast = {:is_atom, [], [:test]}
      assert_eval(ast, true)

      ast = {:is_atom, [], ["test"]}
      assert_eval(ast, false)
    end

    test "is_binary" do
      ast = {:is_binary, [], ["test"]}
      assert_eval(ast, true)

      ast = {:is_binary, [], [:test]}
      assert_eval(ast, false)
    end

    test "is_boolean" do
      ast = {:is_boolean, [], [true]}
      assert_eval(ast, true)

      ast = {:is_boolean, [], [1]}
      assert_eval(ast, false)
    end

    test "is_nil" do
      ast = {:is_nil, [], [nil]}
      assert_eval(ast, true)

      ast = {:is_nil, [], [false]}
      assert_eval(ast, false)
    end
  end

  describe "tuple operations" do
    test "tuple_size" do
      ast = {:tuple_size, [], [{:tuple, [], [1, 2, 3]}]}
      assert_eval(ast, 3)
    end

    test "elem" do
      ast = {:elem, [], [{:tuple, [], [1, 2, 3]}, 1]}
      assert_eval(ast, 2)
    end

    test "put_elem" do
      ast = {:put_elem, [], [{:tuple, [], [1, 2, 3]}, 1, 42]}
      assert_eval(ast, {1, 42, 3})
    end

    test "tuple operations in sequence" do
      ast =
        script([
          declare(:t, {:tuple, [], [1, 2, 3]}),
          declare(:t, {:put_elem, [], [var(:t), 1, 42]}),
          {:elem, [], [var(:t), 1]}
        ])

      assert_eval(ast, 42)
    end
  end

  describe "time operations" do
    test "system_time with no args" do
      ast = {:system_time, [], []}
      result = eval_ast(ast)
      assert is_integer(result)
    end

    test "system_time with unit" do
      ast = {:system_time, [], [:second]}
      result = eval_ast(ast)
      assert is_integer(result)
    end

    test "monotonic_time with no args" do
      ast = {:monotonic_time, [], []}
      result = eval_ast(ast)
      assert is_integer(result)
    end

    test "monotonic_time with unit" do
      ast = {:monotonic_time, [], [:millisecond]}
      result = eval_ast(ast)
      assert is_integer(result)
    end
  end

  describe "kernel error cases" do
    test "tuple_size with non-tuple" do
      ast = {:tuple_size, [], [42]}

      assert_raise RuntimeError, ~r/invalid tuple/i, fn ->
        eval_ast(ast)
      end
    end

    test "elem with invalid index" do
      ast = {:elem, [], [{:tuple, [], [1, 2, 3]}, 5]}

      assert_raise RuntimeError, ~r/invalid index/i, fn ->
        eval_ast(ast)
      end
    end

    test "put_elem with invalid index" do
      ast = {:put_elem, [], [{:tuple, [], [1, 2, 3]}, -1, 42]}

      assert_raise RuntimeError, ~r/invalid index/i, fn ->
        eval_ast(ast)
      end
    end

    test "system_time with invalid unit" do
      ast = {:system_time, [], [:invalid_unit]}

      assert_raise RuntimeError, ~r/invalid time unit/i, fn ->
        eval_ast(ast)
      end
    end
  end
end
