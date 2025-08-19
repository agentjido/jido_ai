defmodule Sparq.Integration.TypeOperationsTest do
  use SparqTest.ASTCase

  describe "string operations" do
    test "string concatenation" do
      ast = {:string_concat, [], ["hello", "world"]}
      assert_eval(ast, "helloworld")
    end

    test "converts atom to string" do
      ast = {:atom_to_string, [], [:test]}
      assert_eval(ast, "test")
    end
  end

  describe "list operations" do
    test "constructs list" do
      ast = {:list, [], [1, 2, 3]}
      assert_eval(ast, [1, 2, 3])
    end

    test "cons operation" do
      ast = {:cons, [], [1, [2, 3]]}
      assert_eval(ast, [1, 2, 3])
    end

    test "head operation" do
      ast = {:head, [], [[1, 2, 3]]}
      assert_eval(ast, 1)
    end

    test "tail operation" do
      ast = {:tail, [], [[1, 2, 3]]}
      assert_eval(ast, [2, 3])
    end

    test "empty check" do
      ast = {:empty?, [], [[]]}
      assert_eval(ast, true)

      ast = {:empty?, [], [[1, 2]]}
      assert_eval(ast, false)
    end

    test "list operations in sequence" do
      ast =
        script([
          declare(:list, {:list, [], [1, 2, 3]}),
          {:cons, [], [0, var(:list)]},
          {:head, [], [var(:list)]},
          {:tail, [], [var(:list)]}
        ])

      assert_eval(ast, [2, 3])
    end
  end

  describe "map operations" do
    test "creates empty map" do
      ast = {:map, [], []}
      assert_eval(ast, %{})
    end

    test "map put" do
      ast = {:map_put, [], [{:map, [], []}, :key, "value"]}
      assert_eval(ast, %{key: "value"})
    end

    test "map get" do
      ast =
        script([
          declare(:m, {:map_put, [], [{:map, [], []}, :key, "value"]}),
          {:map_get, [], [var(:m), :key]}
        ])

      assert_eval(ast, "value")
    end

    test "map delete" do
      ast =
        script([
          declare(:m, {:map_put, [], [{:map, [], []}, :key, "value"]}),
          {:map_delete, [], [var(:m), :key]}
        ])

      assert_eval(ast, %{})
    end

    test "nested map operations" do
      ast =
        script([
          declare(:m, {:map, [], []}),
          declare(:m, {:map_put, [], [var(:m), :a, 1]}),
          declare(:m, {:map_put, [], [var(:m), :b, 2]}),
          declare(:m, {:map_delete, [], [var(:m), :a]}),
          {:map_get, [], [var(:m), :b]}
        ])

      assert_eval(ast, 2)
    end
  end

  describe "type error cases" do
    test "head of empty list" do
      ast = {:head, [], [[]]}

      assert_raise RuntimeError, ~r/empty list/i, fn ->
        eval_ast(ast)
      end
    end

    test "tail of empty list" do
      ast = {:tail, [], [[]]}

      assert_raise RuntimeError, ~r/empty list/i, fn ->
        eval_ast(ast)
      end
    end

    test "map_get with invalid key" do
      ast = {:map_get, [], [{:map, [], []}, :nonexistent]}
      assert_eval(ast, nil)
    end
  end
end
