defmodule Sparq.Evaluator.AST do
  @moduledoc """
  Provides utilities for evaluating AST nodes in a consistent way.
  This module helps reduce duplication in the evaluator by providing
  common patterns for AST traversal and evaluation.
  """

  alias Sparq.{Context, Error}
  alias Sparq.Evaluator.Core

  @type eval_result :: {term(), Context.t()} | {:error, Error.t(), Context.t()}

  @doc """
  Evaluates a node with arguments, handling common patterns like:
  - Adding debug traces
  - Evaluating arguments
  - Calling a handler
  - Error handling

  ## Parameters
    * node_type - The type of node being evaluated (for debug messages)
    * meta - Metadata about the node (like line numbers)
    * args - The arguments to evaluate
    * context - The current execution context
    * handler - Function that receives (evaluated_args, context) and returns {result, new_context}

  ## Examples
      iex> AST.eval_with_args("Addition", meta, [1, 2], context, fn [a, b], ctx ->
      ...>   {a + b, ctx}
      ...> end)
      {3, updated_context}
  """
  @type handler_fun :: (list(term()), Context.t() -> eval_result())
  @spec eval_with_args(String.t(), map(), list(term()), Context.t(), handler_fun()) ::
          eval_result()
  def eval_with_args(node_type, meta, args, context, handler) do
    context = Context.maybe_step(context, node_type, meta)
    context = Context.add_trace(context, {:debug, "#{node_type}", args})

    case eval_args(args, context) do
      {resolved_args, ctx} ->
        try do
          handler.(resolved_args, ctx)
        rescue
          e in Error -> {:error, e, ctx}
          e -> {:error, Error.from_exception(e), ctx}
        end

      error ->
        error
    end
  end

  @doc """
  Evaluates a sequence of expressions in a new frame.
  Handles pushing/popping frames and error propagation.

  ## Parameters
    * frame_type - The type of frame to push (:block, :function, etc)
    * meta - Metadata about the sequence
    * exprs - The expressions to evaluate
    * context - The current execution context
    * opts - Options for frame creation

  ## Examples
      iex> AST.eval_in_frame(:block, meta, [1, 2, 3], context, name: "my_block")
      {3, updated_context}
  """
  @spec eval_in_frame(atom(), map(), [term()], Context.t(), keyword()) :: eval_result()
  def eval_in_frame(frame_type, meta, exprs, context, opts \\ []) do
    context = Context.maybe_step(context, "#{frame_type} evaluation", meta)
    opts = Keyword.merge([debug_data: %{meta: meta}], opts)
    context = Context.push_frame(context, frame_type, opts)

    try do
      case Sparq.Evaluator.evaluate_sequence(exprs, context) do
        {value, new_ctx} -> {value, Context.pop_frame(new_ctx)}
        error -> error
      end
    rescue
      e in Error -> {:error, e, Context.pop_frame(context)}
      e -> {:error, Error.from_exception(e), Context.pop_frame(context)}
    end
  end

  @doc """
  Evaluates a comparison operation between two values.
  Handles argument evaluation and comparison.

  ## Parameters
    * op - The comparison operator (:>, :<, :>=, :<=, :==, :!=)
    * meta - Metadata about the operation
    * left - Left operand
    * right - Right operand
    * context - The current execution context

  ## Examples
      iex> AST.eval_comparison(:>, meta, 2, 1, context)
      {true, updated_context}
  """
  @spec eval_comparison(atom(), map(), term(), term(), Context.t()) :: eval_result()
  def eval_comparison(op, meta, left, right, context) do
    eval_with_args("#{op} comparison", meta, [left, right], context, fn [left_val, right_val],
                                                                        ctx ->
      result =
        case op do
          :> -> left_val > right_val
          :< -> left_val < right_val
          :>= -> left_val >= right_val
          :<= -> left_val <= right_val
          :== -> left_val == right_val
          :!= -> left_val != right_val
        end

      {result, ctx}
    end)
  end

  @doc """
  Evaluates a module definition, handling frame creation and state management.

  ## Parameters
    * name - The module name
    * meta - Metadata about the module
    * body - The module body expressions
    * context - The current execution context

  ## Examples
      iex> AST.eval_module(:MyModule, meta, [function_def], context)
      {nil, updated_context}
  """
  @spec eval_module(atom(), map(), [term()], Context.t()) :: eval_result()
  def eval_module(name, meta, body, context) do
    context = Context.maybe_step(context, "Module definition: #{inspect(name)}", meta)
    context = Context.add_trace(context, {:debug, "Module definition", name})

    unless is_atom(name) do
      raise "invalid module name"
    end

    # Check if we're in a valid context for module definition
    case context.current_frame.type do
      :root ->
        # Top-level module definition is allowed
        do_define_module(name, body, context)

      :module ->
        # Nested module definition is allowed - namespace it under parent
        parent_name = context.current_frame.name
        namespaced_name = :"#{parent_name}.#{name}"
        do_define_module(namespaced_name, body, context)

      _ ->
        raise "modules can only be defined at top-level or inside another module"
    end
  end

  @doc """
  Evaluates a function definition, handling closure creation and binding.

  ## Parameters
    * name - The function name
    * args - The function arguments
    * body - The function body
    * context - The current execution context

  ## Examples
      iex> AST.eval_function(:add, [:x, :y], {:+, [], [var(:x), var(:y)]}, context)
      {function, updated_context}
  """
  @spec eval_function(atom(), [term()], term(), Context.t()) :: eval_result()
  def eval_function(name, args, body, context) do
    context = Context.maybe_step(context, "Function definition: #{inspect(name)}", %{})
    context = Context.add_trace(context, {:debug, "Function definition", {name, args}})

    unless is_atom(name) do
      raise "invalid function name"
    end

    # Create function closure
    wrapped_fun = create_function_closure(name, args, body, context)

    case context.current_frame.type do
      :module ->
        # In a module, store function with string name
        {:ok, new_ctx} = Context.declare_variable(context, to_string(name), wrapped_fun)
        {wrapped_fun, new_ctx}

      _ ->
        # Regular function definition
        case Context.declare_variable(context, name, wrapped_fun) do
          {:ok, new_ctx} ->
            new_ctx = Context.add_trace(new_ctx, {:function_def, {name, args}})
            {wrapped_fun, new_ctx}

          {:error, err} ->
            {:error, Error.new(:binding_error, "#{err}"), context}
        end
    end
  end

  @doc """
  Evaluates a function call, handling argument evaluation and frame management.

  ## Parameters
    * module - The module name (or nil for current scope)
    * fun - The function name
    * args - The function arguments
    * context - The current execution context

  ## Examples
      iex> AST.eval_call(:Math, :add, [1, 2], context)
      {3, updated_context}
  """
  @spec eval_call(atom() | nil, atom(), [term()], Context.t()) :: eval_result()
  def eval_call(module, fun, args, context) do
    context =
      Context.maybe_step(context, "Function call: #{inspect(module)}.#{inspect(fun)}", %{})

    context = Context.add_trace(context, {:debug, "Function call", {module, fun, args}})

    case Core.evaluate_args(args, context) do
      {resolved_args, ctx} ->
        # If module is nil, look in current scope
        cond do
          is_nil(module) ->
            case Core.lookup_variable(fun, ctx) do
              {:ok, fun_impl} when is_function(fun_impl) ->
                fun_impl.(resolved_args, ctx)

              _ ->
                raise "undefined function: #{inspect(fun)}/#{length(resolved_args)}"
            end

          is_atom(module) ->
            # First try to find in current module's scope
            case Core.find_module_in_scope(module, ctx) do
              {:ok, mod_frame} ->
                call_module_function(mod_frame, fun, resolved_args, ctx)

              :error ->
                # Try to find in parent module's scope
                case ctx.current_frame.type do
                  :module ->
                    parent_name = ctx.current_frame.name
                    namespaced_name = :"#{parent_name}.#{module}"

                    case ctx.modules[namespaced_name] do
                      nil -> fallback_to_elixir_module(module, fun, resolved_args, ctx)
                      mod_frame -> call_module_function(mod_frame, fun, resolved_args, ctx)
                    end

                  _ ->
                    fallback_to_elixir_module(module, fun, resolved_args, ctx)
                end
            end

          match?({:__aliases__, _, _}, module) ->
            {:__aliases__, _, parts} = module
            mod = Module.concat(parts)
            {result, ctx} = fallback_to_elixir_module(mod, fun, resolved_args, ctx)
            {result, ctx}

          true ->
            fallback_to_elixir_module(module, fun, resolved_args, ctx)
        end

      error ->
        error
    end
  end

  @doc """
  Evaluates an if expression, handling condition evaluation and branch selection.

  ## Parameters
    * condition - The condition to evaluate
    * then_expr - The expression to evaluate if condition is truthy
    * else_expr - The expression to evaluate if condition is falsy
    * context - The current execution context

  ## Examples
      iex> AST.eval_if(true, 1, 2, context)
      {1, updated_context}
  """
  @spec eval_if(term(), term(), term(), Context.t()) :: eval_result()
  def eval_if(condition, then_expr, else_expr, context) do
    case Sparq.Evaluator.evaluate(condition, context) do
      {condition_result, ctx} ->
        if condition_result != false and condition_result != nil do
          Sparq.Evaluator.evaluate(then_expr, ctx)
        else
          Sparq.Evaluator.evaluate(else_expr, ctx)
        end

      error ->
        error
    end
  end

  @doc """
  Evaluates a list of arguments in sequence.
  Returns {[evaluated_values], updated_context}.

  ## Parameters
    * args - The arguments to evaluate
    * context - The current execution context

  ## Examples
      iex> AST.eval_args([1, 2, 3], context)
      {[1, 2, 3], updated_context}
  """
  @spec eval_args([term()], Context.t()) ::
          {[term()], Context.t()} | {:error, Error.t(), Context.t()}
  def eval_args(args, context) do
    context = Context.add_trace(context, {:debug, "Evaluating args", args})

    result =
      Enum.reduce_while(args, {[], context}, fn arg, {values, ctx} ->
        case Sparq.Evaluator.evaluate(arg, ctx) do
          {value, new_ctx} ->
            new_ctx = Context.add_trace(new_ctx, {:debug, "Evaluated arg", {arg, value}})
            {:cont, {values ++ [value], new_ctx}}

          {:error, _, _} = error ->
            {:halt, error}
        end
      end)

    case result do
      {values, ctx} ->
        ctx = Context.add_trace(ctx, {:debug, "Args evaluation result", values})
        {values, ctx}

      error ->
        error
    end
  end

  # Private helpers

  defp create_function_closure(name, args, body, defining_ctx) do
    fn call_args, call_ctx ->
      if length(call_args) != length(args) do
        raise "wrong number of arguments: expected #{length(args)}, got #{length(call_args)}"
      end

      # If we're in a module context, get the module's state and name
      {module_frame, module_name} =
        case defining_ctx.current_frame do
          %{type: :module} = frame -> {frame, frame.name}
          _ -> {nil, nil}
        end

      # push a new function frame
      func_frame_ctx =
        Context.push_frame(call_ctx, :function,
          name: name,
          parent_ref: call_ctx.current_frame.ref
        )

      # If we have module state, merge it into the function frame
      func_frame_ctx =
        if module_frame do
          # Get the current module state from the modules map
          current_mod = call_ctx.modules[module_name]
          current_state = (current_mod && current_mod.state) || %{}

          # Update the function frame with module info
          %{
            func_frame_ctx
            | current_frame: %{
                func_frame_ctx.current_frame
                | variables: Map.merge(current_state, func_frame_ctx.current_frame.variables),
                  parent_ref: module_frame.ref,
                  type: :module_function
              }
          }
        else
          func_frame_ctx
        end

      # bind args
      bound_ctx =
        Enum.zip(args, call_args)
        |> Enum.reduce(func_frame_ctx, fn {param, val}, c ->
          cond do
            match?({:var, _, _}, param) ->
              # e.g. param = {:var, [], :x}
              {:var, _, real_name} = param
              {:ok, c2} = Context.declare_variable(c, real_name, val)
              c2

            is_atom(param) ->
              {:ok, c2} = Context.declare_variable(c, param, val)
              c2
          end
        end)

      # Evaluate function body
      result = Sparq.Evaluator.evaluate(body, bound_ctx)

      case result do
        {val, after_call_ctx} ->
          # If we're in a module, update its state
          after_call_ctx =
            if module_frame do
              # Get the updated state from the function frame
              updated_state = after_call_ctx.current_frame.variables

              # Update the module's state in the modules map
              Map.update!(after_call_ctx, :modules, fn mods ->
                current_mod = Map.get(mods, module_name)

                if current_mod do
                  updated_mod = %{current_mod | state: updated_state}
                  Map.put(mods, module_name, updated_mod)
                else
                  mods
                end
              end)
            else
              after_call_ctx
            end

          # pop function frame
          popped_ctx = Context.pop_frame(after_call_ctx)
          {val, popped_ctx}

        err ->
          err
      end
    end
  end

  defp call_module_function(mod_frame, fun_name, args, context) do
    fun_name = to_string(fun_name)

    case get_in(mod_frame, [:functions, fun_name]) do
      nil ->
        raise "undefined function: #{inspect(fun_name)}/#{length(args)}"

      fun when is_function(fun) ->
        # Create a new frame for function execution with module state
        context =
          Context.push_frame(context, :function,
            name: fun_name,
            variables: mod_frame.state,
            parent_ref: context.current_frame.ref,
            type: :module_function
          )

        # Call the function with args and current module state
        case fun.(args, context) do
          {value, after_call_ctx} ->
            # Get updated state from function frame
            new_state = after_call_ctx.current_frame.variables

            # Update module state in registry
            after_call_ctx = %{
              after_call_ctx
              | modules:
                  Map.update!(after_call_ctx.modules, mod_frame.name, fn mod ->
                    %{mod | state: new_state}
                  end)
            }

            # Pop function frame and return
            {value, Context.pop_frame(after_call_ctx)}

          error ->
            error
        end
    end
  end

  defp fallback_to_elixir_module(module, fun, resolved_args, ctx) do
    try do
      _ = Code.ensure_loaded(module)
      result = apply(module, fun, resolved_args)
      {result, ctx}
    rescue
      _ ->
        case ctx.modules[module] do
          nil -> raise "undefined module: #{inspect(module)}"
          mod_frame -> call_module_function(mod_frame, fun, resolved_args, ctx)
        end
    end
  end

  # Private helper for module definition
  defp do_define_module(mod_name, body, context) do
    # Push module frame and evaluate body
    context =
      Context.push_frame(context, :module,
        name: mod_name,
        parent_ref: context.current_frame.ref,
        variables: %{},
        debug_data: %{module: mod_name}
      )

    case Sparq.Evaluator.evaluate_sequence(body, context) do
      {_value, new_ctx} ->
        # Split variables into functions and state
        {functions, state} =
          Enum.split_with(new_ctx.current_frame.variables, fn {_name, value} ->
            is_function(value)
          end)

        # Create module object with functions and state
        module_object = %{
          type: :module,
          name: mod_name,
          functions: Enum.into(functions, %{}),
          state: Enum.into(state, %{})
        }

        # Store module object in registry
        new_ctx = %{new_ctx | modules: Map.put(new_ctx.modules, mod_name, module_object)}

        # Pop module frame and return
        {nil, Context.pop_frame(new_ctx)}

      error ->
        error
    end
  end
end
