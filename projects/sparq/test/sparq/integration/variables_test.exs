defmodule Sparq.Integration.VariablesTest do
  use SparqTest.ASTCase

  describe "variable declarations" do
    test "declares and reads variables" do
      ast =
        script([
          declare(:x, 42),
          var(:x)
        ])

      assert_eval(ast, 42)
    end

    test "declares multiple variables" do
      ast =
        script([
          declare(:x, 1),
          declare(:y, 2),
          {:+, [], [var(:x), var(:y)]}
        ])

      assert_eval(ast, 3)
    end

    test "supports variable reassignment" do
      ast =
        script([
          declare(:x, 1),
          declare(:x, {:+, [], [var(:x), 1]}),
          var(:x)
        ])

      assert_eval(ast, 2)
    end
  end

  describe "variable scoping" do
    test "maintains block scope isolation" do
      ast =
        script([
          declare(:x, 1),
          block([
            declare(:x, 2),
            declare(:y, 3)
          ]),
          # Should be 1
          var(:x)
        ])

      assert_eval(ast, 1)
    end

    test "allows inner blocks to access outer variables" do
      ast =
        script([
          declare(:x, 1),
          block([
            declare(:y, {:+, [], [var(:x), 1]}),
            var(:y)
          ])
        ])

      assert_eval(ast, 2)
    end

    test "handles nested blocks" do
      ast =
        script([
          declare(:x, 1),
          block([
            declare(:y, 2),
            block([
              declare(:z, {:+, [], [var(:x), var(:y)]}),
              var(:z)
            ])
          ])
        ])

      assert_eval(ast, 3)
    end
  end

  describe "variable errors" do
    test "raises on undefined variable" do
      ast = script([var(:undefined)])

      assert_raise RuntimeError, ~r/undefined variable/i, fn ->
        eval_ast(ast)
      end
    end

    test "raises on out of scope variable" do
      ast =
        script([
          block([
            declare(:x, 1)
          ]),
          # x is out of scope here
          var(:x)
        ])

      assert_raise RuntimeError, ~r/undefined variable/i, fn ->
        eval_ast(ast)
      end
    end
  end
end
