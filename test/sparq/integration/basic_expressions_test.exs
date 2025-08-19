defmodule Sparq.Integration.BasicExpressionsTest do
  use SparqTest.ASTCase

  describe "literal expressions" do
    test "evaluates integers" do
      ast = 42
      assert_eval(ast, 42)
    end

    test "evaluates floats" do
      ast = 3.14
      assert_eval(ast, 3.14)
    end

    test "evaluates strings" do
      ast = "hello"
      assert_eval(ast, "hello")
    end

    test "evaluates atoms" do
      ast = :test
      assert_eval(ast, :test)
    end

    test "evaluates lists" do
      ast = {:list, [], [1, 2, 3]}
      assert_eval(ast, [1, 2, 3])
    end

    test "evaluates tuples" do
      ast = {:tuple, [], [1, 2, 3]}
      assert_eval(ast, {1, 2, 3})
    end

    test "evaluates maps" do
      ast = {:map, [], []}
      assert_eval(ast, %{})
    end

    test "evaluates booleans" do
      ast = true
      assert_eval(ast, true)

      ast = false
      assert_eval(ast, false)
    end

    test "evaluates nil" do
      ast = nil
      assert_eval(ast, nil)
    end
  end

  describe "arithmetic expressions" do
    test "evaluates addition" do
      ast = {:+, [], [2, 3]}
      assert_eval(ast, 5)
    end

    test "evaluates subtraction" do
      ast = {:-, [], [5, 3]}
      assert_eval(ast, 2)
    end

    test "evaluates multiplication" do
      ast = {:*, [], [3, 4]}
      assert_eval(ast, 12)
    end

    test "evaluates division" do
      ast = {:/, [], [10, 2]}
      assert_eval(ast, 5.0)
    end

    test "evaluates nested arithmetic" do
      ast =
        {:+, [],
         [
           {:*, [], [2, 3]},
           {:/, [], [10, 2]}
         ]}

      assert_eval(ast, 11.0)
    end

    test "evaluates arithmetic in script" do
      ast =
        script([
          {:+, [], [1, 2]},
          {:*, [], [3, 4]},
          {:-, [], [10, 5]}
        ])

      assert_eval(ast, 5)
    end
  end
end
