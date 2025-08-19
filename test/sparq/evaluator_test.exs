defmodule Sparq.EvaluatorTest do
  use ExUnit.Case, async: true
  alias Sparq.{Evaluator, Context, Error}

  setup do
    context = Context.new() |> Context.push_frame(:root)
    {:ok, context: context}
  end

  describe "evaluate/2" do
    test "evaluates primitive values", %{context: context} do
      assert {42, _} = Evaluator.evaluate(42, context)
      assert {"test", _} = Evaluator.evaluate("test", context)
      assert {:atom, _} = Evaluator.evaluate(:atom, context)
      assert {true, _} = Evaluator.evaluate(true, context)
      assert {nil, _} = Evaluator.evaluate(nil, context)
      assert {[1, 2, 3], _} = Evaluator.evaluate([1, 2, 3], context)
      assert {%{a: 1}, _} = Evaluator.evaluate(%{a: 1}, context)

      fun = fn -> :ok end
      assert {^fun, _} = Evaluator.evaluate(fun, context)
    end

    test "evaluates empty block", %{context: context} do
      block = {:block, [line: 1], []}
      assert {nil, ctx} = Evaluator.evaluate(block, context)
      assert :queue.len(ctx.call_stack) > 0
      assert ctx.current_frame.type == :root
    end

    test "evaluates single expression block", %{context: context} do
      block = {:block, [line: 1], [42]}
      assert {42, ctx} = Evaluator.evaluate(block, context)
      assert :queue.len(ctx.call_stack) > 0
      assert ctx.current_frame.type == :root
    end

    test "evaluates multiple expressions in block", %{context: context} do
      block = {:block, [line: 1], [1, 2, 3]}
      assert {3, ctx} = Evaluator.evaluate(block, context)
      assert :queue.len(ctx.call_stack) > 0
      assert ctx.current_frame.type == :root
    end

    test "maintains lexical scoping in nested blocks", %{context: context} do
      block =
        {:block, [line: 1],
         [
           {:bind, [line: 1], [:x, 1, :let]},
           {:block, [line: 2],
            [
              {:bind, [line: 2], [:y, 2, :let]},
              {:+, [line: 2], [{:var, [line: 2], :x}, {:var, [line: 2], :y}]}
            ]}
         ]}

      assert {3, _ctx} = Evaluator.evaluate(block, context)
    end

    test "propagates errors from inner expressions", %{context: context} do
      block =
        {:block, [line: 1],
         [
           1,
           {:var, [line: 2], :undefined},
           3
         ]}

      assert {:error, %Error{type: :undefined_variable}, _} = Evaluator.evaluate(block, context)
    end

    test "evaluates variable access", %{context: context} do
      context =
        context
        |> Context.declare_variable(:x, 42)
        |> then(fn {:ok, ctx} -> ctx end)

      assert {42, ctx} = Evaluator.evaluate({:var, [line: 1], :x}, context)
      assert :queue.len(ctx.event_history) > 0

      # Undefined variable
      assert {:error, %Error{type: :undefined_variable}, _} =
               Evaluator.evaluate({:var, [line: 1], :y}, context)
    end

    test "evaluates variable bindings", %{context: context} do
      # Let binding
      assert {42, ctx} =
               Evaluator.evaluate(
                 {:bind, [line: 1], [:x, 42, :let]},
                 context
               )

      assert {:ok, 42} = Context.lookup_variable(ctx, :x)

      # Const binding
      assert {10, ctx} =
               Evaluator.evaluate(
                 {:bind, [line: 1], [:y, 10, :const]},
                 context
               )

      assert {:ok, {:const, 10}} = Context.lookup_variable(ctx, :y)

      # Invalid declaration type
      assert {:error, %Error{type: :invalid_declaration}, _} =
               Evaluator.evaluate(
                 {:bind, [line: 1], [:z, 1, :invalid]},
                 context
               )
    end

    test "evaluates function definitions", %{context: context} do
      fun_def =
        {:function, [line: 1],
         [:add, [:x, :y], {:+, [line: 1], [{:var, [line: 1], :x}, {:var, [line: 1], :y}]}]}

      assert {fun, ctx} = Evaluator.evaluate(fun_def, context)
      assert is_function(fun)

      # Test function execution
      {result, _} = fun.([1, 2], ctx)
      assert result == 3
    end

    test "evaluates module definitions", %{context: context} do
      module_def =
        {:module, [line: 1],
         [
           {:name, [line: 1], [:Math]},
           {:function, [line: 2],
            [:add, [:x, :y], {:+, [line: 2], [{:var, [line: 2], :x}, {:var, [line: 2], :y}]}]}
         ]}

      assert {nil, ctx} = Evaluator.evaluate(module_def, context)
      # Module context is temporary
      assert ctx.module == nil

      # Function should be available in module namespace
      mod_frame = ctx.modules[:Math]
      fun = Sparq.Frame.get_variable(mod_frame, "add")
      assert is_function(fun)

      # Test function execution
      {result, _} = fun.([1, 2], ctx)
      assert result == 3
    end

    test "evaluates if expressions", %{context: context} do
      if_expr = {:if, [line: 1], [true, 1, 2]}
      assert {1, _} = Evaluator.evaluate(if_expr, context)

      if_expr = {:if, [line: 1], [false, 1, 2]}
      assert {2, _} = Evaluator.evaluate(if_expr, context)

      if_expr = {:if, [line: 1], [nil, 1, 2]}
      assert {2, _} = Evaluator.evaluate(if_expr, context)
    end

    test "evaluates module function calls", %{context: context} do
      # Test Elixir module call
      call = {{:call, [line: 1], [{:__aliases__, [line: 1], [:String]}, :upcase]}, [], ["hello"]}
      assert {"HELLO", _} = Evaluator.evaluate(call, context)

      # Test user-defined module call
      module_def =
        {:module, [line: 1],
         [
           {:name, [line: 1], [:Math]},
           {:function, [line: 2],
            [:add, [:x, :y], {:+, [line: 2], [{:var, [line: 2], :x}, {:var, [line: 2], :y}]}]}
         ]}

      {_, context} = Evaluator.evaluate(module_def, context)

      call = {{:call, [line: 1], [:Math, :add]}, [], [1, 2]}
      assert {3, _} = Evaluator.evaluate(call, context)

      # Test undefined module
      call = {{:call, [line: 1], [:Undefined, :fun]}, [], []}

      assert_raise RuntimeError, ~r/undefined module/, fn ->
        Evaluator.evaluate(call, context)
      end
    end
  end

  describe "evaluate_sequence/2" do
    test "evaluates empty sequence" do
      context = Context.new()
      assert {nil, _} = Evaluator.evaluate_sequence([], context)
    end

    test "evaluates single expression" do
      context = Context.new()
      assert {42, _} = Evaluator.evaluate_sequence([42], context)
    end

    test "evaluates multiple expressions" do
      context = Context.new()
      assert {3, _} = Evaluator.evaluate_sequence([1, 2, 3], context)
    end

    test "propagates errors" do
      context = Context.new()

      assert {:error, %Error{}, _} =
               Evaluator.evaluate_sequence(
                 [1, {:var, [line: 1], :undefined}, 3],
                 context
               )
    end
  end

  describe "evaluate_args/2" do
    test "evaluates list of arguments", %{context: context} do
      {:ok, context} = Context.declare_variable(context, :x, 2)

      args = [1, {:var, [line: 1], :x}, 3]
      assert {[1, 2, 3], _} = Evaluator.evaluate_args(args, context)
    end

    test "propagates errors in argument evaluation", %{context: context} do
      args = [1, {:var, [line: 1], :undefined}, 3]

      assert {:error, %Error{type: :undefined_variable}, _} =
               Evaluator.evaluate_args(args, context)
    end
  end
end
