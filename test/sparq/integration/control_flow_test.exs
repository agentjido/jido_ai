defmodule Sparq.Integration.ControlFlowTest do
  use SparqTest.ASTCase

  describe "if expressions" do
    test "evaluates true branch" do
      ast = {:if, [], [true, 1, 2]}
      assert_eval(ast, 1)
    end

    test "evaluates false branch" do
      ast = {:if, [], [false, 1, 2]}
      assert_eval(ast, 2)
    end

    test "evaluates nil as false" do
      ast = {:if, [], [nil, 1, 2]}
      assert_eval(ast, 2)
    end

    test "evaluates zero as truthy" do
      ast = {:if, [], [0, 1, 2]}
      assert_eval(ast, 1)
    end

    test "evaluates complex conditions" do
      ast = {:if, [], [{:>, [], [5, 3]}, "greater", "lesser"]}
      assert_eval(ast, "greater")
    end

    test "nested if expressions" do
      ast =
        {:if, [],
         [
           {:>, [], [5, 3]},
           {:if, [], [{:>, [], [10, 5]}, "first", "second"]},
           "third"
         ]}

      assert_eval(ast, "first")
    end

    test "if with variable conditions" do
      ast =
        script([
          declare(:x, 10),
          {:if, [], [{:>, [], [var(:x), 5]}, "greater", "lesser"]}
        ])

      assert_eval(ast, "greater")
    end
  end

  describe "block expressions" do
    test "evaluates simple block" do
      ast =
        {:block, [],
         [
           {:+, [], [1, 2]},
           {:*, [], [3, 4]}
         ]}

      assert_eval(ast, 12)
    end

    test "block with declarations" do
      ast =
        {:block, [],
         [
           declare(:x, 1),
           declare(:y, 2),
           {:+, [], [var(:x), var(:y)]}
         ]}

      assert_eval(ast, 3)
    end

    test "nested blocks" do
      ast =
        {:block, [],
         [
           declare(:x, 1),
           {:block, [],
            [
              declare(:y, {:+, [], [var(:x), 1]}),
              {:+, [], [var(:x), var(:y)]}
            ]}
         ]}

      assert_eval(ast, 3)
    end

    test "block variables don't leak" do
      ast =
        script([
          {:block, [],
           [
             declare(:x, 1),
             {:+, [], [var(:x), 1]}
           ]},
          var(:x)
        ])

      assert_raise RuntimeError, ~r/undefined variable/i, fn ->
        eval_ast(ast)
      end
    end
  end
end
