defmodule Sparq.Evaluator.VariableBinding do
  @moduledoc """
  Handles variable binding operations in the Sparq language.
  This module centralizes all variable binding logic to ensure consistent behavior
  across different binding contexts (pattern matching, direct binding, etc).
  """

  alias Sparq.{Context, Error}
  alias Sparq.Evaluator.Core

  @doc """
  Handles variable binding with different declaration types (:let or :const).
  Returns {value, context} tuple or raises an Error for invalid operations.

  ## Parameters
    * context - The current execution context
    * name - The name of the variable to bind
    * value - The value to bind to the variable
    * declaration_type - The type of declaration (:let or :const)

  ## Examples
      iex> context = Context.new()
      iex> {42, new_ctx} = VariableBinding.handle_variable_binding(context, :x, 42, :const)
      iex> Context.lookup_variable(new_ctx, :x)
      {:ok, {:const, 42}}
  """
  @spec handle_variable_binding(Context.t(), atom(), term(), atom()) :: {term(), Context.t()}
  def handle_variable_binding(context, name, value, :const) do
    case Context.lookup_variable(context, name) do
      {:ok, {:const, _}} ->
        raise Error.new(:binding_error, "Cannot redeclare constant: #{inspect(name)}")

      _ ->
        case Context.declare_constant(context, name, value) do
          {:ok, ctx} -> {value, ctx}
          {:error, err} -> raise Error.new(:binding_error, "#{err}")
        end
    end
  end

  def handle_variable_binding(context, name, value, :let) do
    case context.current_frame.type do
      :module_function ->
        handle_module_function_binding(context, name, value)

      :function when context.current_frame.parent_ref != nil ->
        handle_function_binding(context, name, value)

      :module ->
        handle_module_binding(context, name, value)

      _ ->
        handle_regular_binding(context, name, value)
    end
  end

  def handle_variable_binding(_context, _name, _value, other) do
    raise Error.new(:invalid_declaration, "Invalid declaration type: #{inspect(other)}")
  end

  # Private helper functions for different binding contexts

  defp handle_module_function_binding(context, name, value) do
    case Context.declare_variable(context, name, value) do
      {:ok, ctx} ->
        {value, ctx}

      {:error, :variable_already_exists} ->
        case Context.update_variable(context, name, value) do
          {:ok, ctx} -> {value, ctx}
          {:error, err} -> raise Error.new(:binding_error, "#{err}")
        end

      {:error, err} ->
        raise Error.new(:binding_error, "#{err}")
    end
  end

  defp handle_function_binding(context, name, value) do
    parent_frame = Core.find_frame_in_stack(context.current_frame.parent_ref, context)

    if parent_frame && parent_frame.type == :module do
      handle_module_parent_binding(context, parent_frame, name, value)
    else
      handle_regular_binding(context, name, value)
    end
  end

  defp handle_module_parent_binding(context, parent_frame, name, value) do
    case Context.declare_variable(%{context | current_frame: parent_frame}, name, value) do
      {:ok, ctx} ->
        update_module_and_restore_frame(ctx, parent_frame, value, context)

      {:error, :variable_already_exists} ->
        case Context.update_variable(%{context | current_frame: parent_frame}, name, value) do
          {:ok, ctx} -> update_module_and_restore_frame(ctx, parent_frame, value, context)
          {:error, err} -> raise Error.new(:binding_error, "#{err}")
        end

      {:error, err} ->
        raise Error.new(:binding_error, "#{err}")
    end
  end

  defp handle_module_binding(context, name, value) do
    case Context.declare_variable(context, name, value) do
      {:ok, ctx} ->
        update_module_frame(ctx, value)

      {:error, :variable_already_exists} ->
        case Context.update_variable(context, name, value) do
          {:ok, ctx} -> update_module_frame(ctx, value)
          {:error, err} -> raise Error.new(:binding_error, "#{err}")
        end

      {:error, err} ->
        raise Error.new(:binding_error, "#{err}")
    end
  end

  defp handle_regular_binding(context, name, value) do
    case Context.lookup_variable(context, name) do
      {:ok, {:const, _}} ->
        raise Error.new(:binding_error, "Cannot reassign constant: #{inspect(name)}")

      _ ->
        case Context.declare_variable(context, name, value) do
          {:ok, ctx} ->
            {value, ctx}

          {:error, :variable_already_exists} ->
            case Context.update_variable(context, name, value) do
              {:ok, ctx} -> {value, ctx}
              {:error, err} -> raise Error.new(:binding_error, "#{err}")
            end

          {:error, err} ->
            raise Error.new(:binding_error, "#{err}")
        end
    end
  end

  # Helper functions for updating module state

  defp update_module_frame(ctx, value) do
    updated_ctx =
      Map.update!(ctx, :modules, fn mods ->
        Map.put(mods, ctx.current_frame.name, ctx.current_frame)
      end)

    {value, updated_ctx}
  end

  defp update_module_and_restore_frame(ctx, parent_frame, value, original_context) do
    updated_ctx =
      Map.update!(ctx, :modules, fn mods ->
        Map.put(mods, parent_frame.name, ctx.current_frame)
      end)

    {value, %{original_context | modules: updated_ctx.modules}}
  end
end
