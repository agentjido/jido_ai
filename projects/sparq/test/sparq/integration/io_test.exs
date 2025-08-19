defmodule Sparq.Integration.IOTest do
  use SparqTest.ASTCase

  describe "IO operations" do
    test "print returns value" do
      ast = {:print, [], ["hello"]}
      assert_eval(ast, "hello")
    end

    test "print numbers" do
      ast = {:print, [], [42]}
      assert_eval(ast, 42)
    end

    test "print complex expressions" do
      ast = {:print, [], [{:+, [], [2, 3]}]}
      assert_eval(ast, 5)
    end

    test "print in script" do
      ast =
        script([
          {:print, [], ["first"]},
          {:print, [], ["second"]}
        ])

      assert_eval(ast, "second")
    end

    test "print with variables" do
      ast =
        script([
          declare(:message, "Hello"),
          {:print, [], [var(:message)]}
        ])

      assert_eval(ast, "Hello")
    end
  end

  describe "IO error cases" do
    test "print with wrong arity" do
      ast = {:print, [], []}

      assert_raise RuntimeError, ~r/invalid arity/i, fn ->
        eval_ast(ast)
      end
    end

    test "print with multiple arguments" do
      ast = {:print, [], ["one", "two"]}

      assert_raise RuntimeError, ~r/invalid arity/i, fn ->
        eval_ast(ast)
      end
    end
  end
end
