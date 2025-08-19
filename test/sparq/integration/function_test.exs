defmodule Sparq.Integration.FunctionTest do
  use SparqTest.ASTCase

  describe "function definitions" do
    test "defines and calls simple function" do
      ast =
        script([
          {:function, [], [:double, [:x], {:*, [], [var(:x), 2]}]},
          {{:call, [], [nil, :double]}, [], [21]}
        ])

      assert_eval(ast, 42)
    end

    test "functions with multiple arguments" do
      ast =
        script([
          {:function, [],
           [:sum, [:a, :b, :c], {:+, [], [var(:a), {:+, [], [var(:b), var(:c)]}]}]},
          {{:call, [], [nil, :sum]}, [], [1, 2, 3]}
        ])

      assert_eval(ast, 6)
    end

    test "functions with complex bodies" do
      ast =
        script([
          {:function, [],
           [
             :conditional_add,
             [:x, :y],
             {:if, [], [{:>, [], [var(:x), var(:y)]}, {:+, [], [var(:x), var(:y)]}, var(:y)]}
           ]},
          {{:call, [], [nil, :conditional_add]}, [], [5, 3]},
          {{:call, [], [nil, :conditional_add]}, [], [2, 3]}
        ])

      assert_eval(ast, 3)
    end

    # Removed skip tag here so it runs
    test "recursive functions" do
      ast =
        script([
          {:function, [],
           [
             :factorial,
             [:n],
             {:if, [],
              [
                {:>, [], [var(:n), 1]},
                {:*, [],
                 [var(:n), {{:call, [], [nil, :factorial]}, [], [{:-, [], [var(:n), 1]}]}]},
                1
              ]}
           ]},
          {{:call, [], [nil, :factorial]}, [], [5]}
        ])

      assert_eval(ast, 120)
    end

    test "functions maintaining closure scope" do
      ast =
        script([
          declare(:multiplier, 2),
          {:function, [], [:apply_multiplier, [:x], {:*, [], [var(:x), var(:multiplier)]}]},
          {{:call, [], [nil, :apply_multiplier]}, [], [21]}
        ])

      assert_eval(ast, 42)
    end
  end

  describe "function error cases" do
    test "calling undefined function" do
      ast = {{:call, [], [nil, :undefined]}, [], []}

      assert_raise RuntimeError, ~r/undefined function/i, fn ->
        eval_ast(ast)
      end
    end

    test "wrong number of arguments" do
      ast =
        script([
          {:function, [], [:add, [:a, :b], {:+, [], [var(:a), var(:b)]}]},
          {{:call, [], [nil, :add]}, [], [1]}
        ])

      assert_raise RuntimeError, ~r/wrong number of arguments/i, fn ->
        eval_ast(ast)
      end
    end

    test "invalid function name" do
      ast =
        script([
          {:function, [], [123, [:x], var(:x)]}
        ])

      assert_raise RuntimeError, ~r/invalid function name/i, fn ->
        eval_ast(ast)
      end
    end
  end
end
