defmodule Sparq.Evaluator.Core do
  alias Sparq.Context

  @doc """
  Evaluates a list of arguments in sequence.
  Returns {[evaluated_values], updated_context}.
  """
  def evaluate_args(args, context) do
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

  @doc """
  Looks up a variable in the current context, traversing the frame stack.
  Returns {:ok, value} if found, {:error, :undefined_variable} if not found.
  """
  def lookup_variable(name, context) do
    case do_lookup_variable(name, context.current_frame, context) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :undefined_variable}
    end
  end

  defp do_lookup_variable(_name, nil, _context), do: :error

  defp do_lookup_variable(name, frame, context) do
    name = to_string(name)

    case Map.get(frame.variables, name) do
      nil ->
        case frame.parent_ref do
          nil ->
            :error

          parent_ref ->
            parent_frame = find_frame_in_stack(parent_ref, context)

            case parent_frame do
              nil ->
                :error

              # For functions in modules, allow access to module variables
              %{type: :module} when frame.type == :function ->
                do_lookup_variable(name, parent_frame, context)

              # For modules, only look up in module scope
              %{type: :module} ->
                :error

              # For other frames, continue lookup
              frame ->
                do_lookup_variable(name, frame, context)
            end
        end

      {:const, _} = value ->
        {:ok, value}

      value when is_map(value) ->
        # If we found a module in variables, return it
        if Map.get(value, :type) == :module do
          {:ok, value}
        else
          {:ok, value}
        end

      value ->
        {:ok, value}
    end
  end

  @doc """
  Helper function to find a frame in the call stack by its reference.
  """
  def find_frame_in_stack(ref, context) do
    context.call_stack
    |> :queue.to_list()
    |> Enum.find(&(&1.ref == ref))
  end

  @doc """
  Helper to get parent module name from a namespaced module name.
  """
  def get_parent_module_name(module_name) when is_atom(module_name) do
    module_name
    |> Atom.to_string()
    |> String.split(".")
    |> case do
      [_single] ->
        nil

      parts ->
        parts |> Enum.reverse() |> tl() |> Enum.reverse() |> Enum.join(".") |> String.to_atom()
    end
  end

  @doc """
  Helper for finding module in current scope.
  """
  def find_module_in_scope(module_name, context) do
    case context.current_frame.type do
      :module ->
        # If we're in a module, first check if the requested module is a child
        parent_name = context.current_frame.name
        namespaced_name = :"#{parent_name}.#{module_name}"

        case context.modules[namespaced_name] do
          nil ->
            # If not found as child, check if it's a sibling (share same parent)
            case get_parent_module_name(parent_name) do
              nil ->
                # No parent, check global
                case context.modules[module_name] do
                  nil -> :error
                  mod_frame -> {:ok, mod_frame}
                end

              parent ->
                # Check for sibling under same parent
                sibling_name = :"#{parent}.#{module_name}"

                case context.modules[sibling_name] do
                  nil ->
                    # Not found as sibling, check global
                    case context.modules[module_name] do
                      nil -> :error
                      mod_frame -> {:ok, mod_frame}
                    end

                  mod_frame ->
                    {:ok, mod_frame}
                end
            end

          mod_frame ->
            {:ok, mod_frame}
        end

      _ ->
        # Otherwise just check global modules
        case context.modules[module_name] do
          nil -> :error
          mod_frame -> {:ok, mod_frame}
        end
    end
  end

  @doc """
  Helper for finding a module in the parent frame chain.
  """
  def find_module_in_parent(_module_name, nil, _context), do: :error

  def find_module_in_parent(module_name, frame, context) do
    case frame.type do
      :module ->
        if frame.name == module_name do
          {:ok, frame}
        else
          parent_frame = find_frame_in_stack(frame.parent_ref, context)
          find_module_in_parent(module_name, parent_frame, context)
        end

      _ ->
        parent_frame = find_frame_in_stack(frame.parent_ref, context)
        find_module_in_parent(module_name, parent_frame, context)
    end
  end
end
