defmodule Sparq.Evaluator do
  @moduledoc """
  Handles evaluation of Sparq expressions within an execution context.
  """

  # use ExDbug, enabled: false
  # @decorate_all dbug()

  alias Sparq.{Context, Error}

  alias Sparq.Evaluator.{
    Core,
    Sequence,
    Bind,
    AST,
    Script
  }

  @whitespace_token_types [:spaces, :newline, :line_comment, :block_comment]

  @type eval_result ::
          {term(), Context.t()}
          | {:error, Error.t(), Context.t()}

  @doc """
  Evaluates a sequence of expressions in order, returning the result of the last one.
  Maintains proper frame isolation.
  """
  @spec evaluate_sequence([term()], Context.t()) :: eval_result()
  def evaluate_sequence([], context), do: {nil, context}

  def evaluate_sequence([expr], context) do
    Sequence.evaluate_sequence([expr], context)
  end

  def evaluate_sequence([expr | rest], context) do
    Sequence.evaluate_sequence([expr | rest], context)
  end

  @doc """
  Evaluates a single expression in the given context.
  Returns {result, updated_context}.
  """
  @spec evaluate(term(), Context.t()) :: eval_result()
  def evaluate(expr, context)

  # Direct value handling (primitives pass-through)
  def evaluate(value, context)
      when is_number(value) or is_binary(value) or is_atom(value) or
             is_boolean(value) or is_nil(value) or is_list(value) or
             is_map(value) or is_function(value) do
    {value, context}
  end

  # Function definitions
  def evaluate({:function, _meta, [name, args, body]}, context) do
    AST.eval_function(name, args, body, context)
  end

  # Tuple evaluation
  def evaluate({:tuple, meta, elements}, context) do
    context = Context.maybe_step(context, "Tuple construction", meta)

    case AST.eval_args(elements, context) do
      {resolved_elements, ctx} ->
        tuple_value = List.to_tuple(resolved_elements)
        ctx = Context.add_trace(ctx, {:debug, "Tuple elements", resolved_elements})
        {tuple_value, ctx}

      error ->
        error
    end
  end

  # Script evaluation
  def evaluate({:script, meta, []}, context) do
    context = Context.maybe_step(context, "Empty script evaluation", meta)
    {nil, context}
  end

  def evaluate({:script, meta, exprs}, context) do
    context = Context.maybe_step(context, "Script evaluation", meta)
    filtered_exprs = filter_whitespace(exprs)

    Enum.reduce_while(filtered_exprs, {nil, context}, fn expr, {_last_result, ctx} ->
      case evaluate(expr, ctx) do
        {result, new_ctx} -> {:cont, {result, new_ctx}}
        {:error, _reason, _ctx} = error -> {:halt, error}
      end
    end)
  end

  # Block evaluation
  def evaluate({:block, meta, exprs}, context) do
    AST.eval_in_frame(:block, meta, exprs, context, name: "block")
  end

  # Control flow
  def evaluate({:if, meta, [condition, then_expr, else_expr]}, context) do
    context = Context.maybe_step(context, "If expression", meta)
    AST.eval_if(condition, then_expr, else_expr, context)
  end

  # Comparison operators
  def evaluate({:>, meta, [left, right]}, context) do
    AST.eval_comparison(:>, meta, left, right, context)
  end

  def evaluate({:<, meta, [left, right]}, context) do
    AST.eval_comparison(:<, meta, left, right, context)
  end

  def evaluate({:>=, meta, [left, right]}, context) do
    AST.eval_comparison(:>=, meta, left, right, context)
  end

  def evaluate({:<=, meta, [left, right]}, context) do
    AST.eval_comparison(:<=, meta, left, right, context)
  end

  def evaluate({:==, meta, [left, right]}, context) do
    AST.eval_comparison(:==, meta, left, right, context)
  end

  def evaluate({:!=, meta, [left, right]}, context) do
    AST.eval_comparison(:!=, meta, left, right, context)
  end

  # Variable operations
  def evaluate({:var, meta, name}, context) do
    context = Context.maybe_step(context, "Variable access: #{inspect(name)}", meta)

    case Core.lookup_variable(name, context) do
      {:ok, value} ->
        new_ctx = Context.add_trace(context, {:var_access, {name, value}})
        {value, new_ctx}

      {:error, :undefined_variable} ->
        {:error, Error.new(:undefined_variable, "Undefined variable: #{inspect(name)}"), context}
    end
  end

  # Variable binding
  def evaluate({:bind, meta, [pattern, value, declaration_type]}, context) do
    context = Context.maybe_step(context, "Variable binding", meta)
    Bind.handle_bind(pattern, value, declaration_type, context)
  end

  # Module definition
  def evaluate({:module, meta, [{:name, _, [mod_name]} | body]}, context) do
    AST.eval_module(mod_name, meta, body, context)
  end

  # Module function call
  def evaluate({{:call, _meta, [module, fun]}, _ctx_meta, args}, context) do
    AST.eval_call(module, fun, args, context)
  end

  # Script constructs
  def evaluate({:character, meta, _args} = node, context) do
    context = Context.maybe_step(context, "Character definition", meta)
    Script.evaluate_character(node, context)
  end

  def evaluate({:scene, meta, _args} = node, context) do
    context = Context.maybe_step(context, "Scene definition", meta)
    Script.evaluate_scene(node, context)
  end

  # Operation evaluation (catch-all for other operations)
  def evaluate({op, meta, args}, context) when is_atom(op) do
    AST.eval_with_args("Operation: #{inspect(op)}", meta, args, context, fn resolved_args, ctx ->
      handler = Sparq.Handlers.Registry.get_handler(op)

      case apply(handler, :validate, [op, resolved_args]) do
        :ok ->
          apply(handler, :handle, [op, meta, resolved_args, ctx])

        {:error, :invalid_arity} ->
          raise "invalid arity"

        {:error, :empty_list} ->
          raise "empty list"

        {:error, reason} ->
          raise "invalid #{reason}"
      end
    end)
  end

  @doc """
  Filters out whitespace and comment tokens from a list of expressions.
  """
  def filter_whitespace(exprs) when is_list(exprs) do
    Enum.reject(exprs, fn
      {type, _meta, _args} -> type in @whitespace_token_types
      _ -> false
    end)
  end

  def filter_whitespace(expr), do: expr

  # Helper functions for frame lookup
  defp find_frame_in_stack(ref, context) do
    Core.find_frame_in_stack(ref, context)
  end

  # Helper for finding module in current scope
  defp find_module_in_scope(module_name, context) do
    Core.find_module_in_scope(module_name, context)
  end

  # Helper to get parent module name from a namespaced module name
  defp get_parent_module_name(module_name) when is_atom(module_name) do
    Core.get_parent_module_name(module_name)
  end

  defp find_module_in_parent(module_name, frame, context) do
    Core.find_module_in_parent(module_name, frame, context)
  end

  defp lookup_variable(name, context) do
    Core.lookup_variable(name, context)
  end

  defp pop_frame({value, context}), do: {value, Context.pop_frame(context)}
  defp pop_frame({:error, _, _} = error), do: error

  @doc """
  Evaluates a list of arguments in sequence.
  Returns {[evaluated_values], updated_context}.
  """
  def evaluate_args(args, context) do
    AST.eval_args(args, context)
  end
end
