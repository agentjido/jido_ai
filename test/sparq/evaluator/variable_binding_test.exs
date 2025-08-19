defmodule Sparq.Evaluator.VariableBindingTest do
  use ExUnit.Case, async: true
  alias Sparq.{Context, Error, Frame}
  alias Sparq.Evaluator.VariableBinding

  setup do
    context = Context.new()
    frame = Frame.new(type: :root)
    context = %{context | current_frame: frame}
    {:ok, context: context}
  end

  describe "handle_variable_binding/4" do
    test "binds const variables", %{context: context} do
      {value, ctx} = VariableBinding.handle_variable_binding(context, :x, 42, :const)
      assert value == 42
      assert {:ok, {:const, 42}} = Context.lookup_variable(ctx, :x)
    end

    test "prevents rebinding const variables", %{context: context} do
      {_, ctx} = VariableBinding.handle_variable_binding(context, :x, 42, :const)

      assert_raise Error, "Cannot redeclare constant: :x", fn ->
        VariableBinding.handle_variable_binding(ctx, :x, 43, :const)
      end
    end

    test "allows let variables to be rebound", %{context: context} do
      {_, ctx} = VariableBinding.handle_variable_binding(context, :x, 42, :let)
      {value, ctx} = VariableBinding.handle_variable_binding(ctx, :x, 43, :let)
      assert value == 43
      assert {:ok, 43} = Context.lookup_variable(ctx, :x)
    end

    test "handles module function bindings", %{context: context} do
      frame = %{context.current_frame | type: :module_function}
      context = %{context | current_frame: frame}
      {value, ctx} = VariableBinding.handle_variable_binding(context, :x, 42, :let)
      assert value == 42
      assert {:ok, 42} = Context.lookup_variable(ctx, :x)
    end

    test "handles module bindings", %{context: context} do
      frame = %{context.current_frame | type: :module, name: :test_module}
      context = %{context | current_frame: frame, modules: %{}}
      {value, ctx} = VariableBinding.handle_variable_binding(context, :x, 42, :let)
      assert value == 42
      assert {:ok, 42} = Context.lookup_variable(ctx, :x)
      assert Map.has_key?(ctx.modules, :test_module)
    end

    test "raises on invalid declaration type", %{context: context} do
      assert_raise Error, "Invalid declaration type: :invalid", fn ->
        VariableBinding.handle_variable_binding(context, :x, 42, :invalid)
      end
    end

    test "prevents reassigning constants with let", %{context: context} do
      {_, ctx} = VariableBinding.handle_variable_binding(context, :x, 42, :const)

      assert_raise Error, "Cannot reassign constant: :x", fn ->
        VariableBinding.handle_variable_binding(ctx, :x, 43, :let)
      end
    end
  end
end
