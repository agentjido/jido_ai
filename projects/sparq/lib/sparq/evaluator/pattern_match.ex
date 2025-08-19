defmodule Sparq.Evaluator.PatternMatch do
  alias Sparq.{Context, Error}
  alias Sparq.Evaluator.VariableBinding

  @type binding_result :: {:ok, term(), Context.t()} | {:error, Error.t(), Context.t()}

  @doc """
  Pattern matches a value against a pattern.
  Returns {:ok, bindings} where bindings is a map of variable names to values.
  """
  @spec match(term(), term()) :: {:ok, map()}
  def match(pattern, value) do
    try do
      {:ok, do_match(pattern, value)}
    rescue
      e in Error -> raise e
      _ -> raise Error.new(:match_error, "Pattern match failed")
    end
  end

  @doc """
  Applies a set of bindings to the context.
  Returns {:ok, value, context} or {:error, error, context}.
  """
  @spec apply_bindings(Context.t(), map(), atom()) :: binding_result()
  def apply_bindings(context, bindings, decl_type) do
    try do
      {value, new_ctx} =
        Enum.reduce(bindings, {nil, context}, fn {var, val}, {_res, ctx} ->
          if val == :_pass_through do
            {nil, ctx}
          else
            {val, do_bind_variable(ctx, var, val, decl_type)}
          end
        end)

      {:ok, value, new_ctx}
    rescue
      e in Error -> {:error, e, context}
    end
  end

  defp do_bind_variable(context, name, value, decl_type) do
    case VariableBinding.handle_variable_binding(context, name, value, decl_type) do
      {_val, ctx} -> ctx
    end
  end

  # Pattern matching implementation
  defp do_match({:var, _, name}, value) when is_atom(name), do: %{name => value}
  defp do_match(:_, _value), do: %{}
  defp do_match(pattern, value) when is_atom(pattern), do: %{pattern => value}

  # Handle old tuple format
  defp do_match({:tuple, meta, vars}, value) when is_list(meta) do
    values =
      cond do
        is_tuple(value) -> Tuple.to_list(value)
        is_list(value) -> value
        true -> nil
      end

    if values && length(vars) == length(values) do
      Enum.zip(vars, values)
      |> Enum.reduce(%{}, fn {var, val}, acc ->
        Map.merge(acc, do_match(var, val))
      end)
    else
      raise Error.new(:match_error, "Tuple size mismatch")
    end
  end

  # Handle new tuple format
  defp do_match({:tuple, elements}, value) when is_tuple(value) do
    value_list = Tuple.to_list(value)

    if length(elements) != length(value_list) do
      raise Error.new(:match_error, "Tuple size mismatch")
    end

    Enum.zip(elements, value_list)
    |> Enum.reduce(%{}, fn {pat, val}, acc ->
      Map.merge(acc, do_match(pat, val))
    end)
  end

  # Handle old list format
  defp do_match(list_pattern, value) when is_list(list_pattern) and is_list(value) do
    if length(list_pattern) == length(value) do
      Enum.zip(list_pattern, value)
      |> Enum.reduce(%{}, fn {pat, val}, acc ->
        Map.merge(acc, do_match(pat, val))
      end)
    else
      raise Error.new(:match_error, "List length mismatch")
    end
  end

  # Handle new list format
  defp do_match({:list, elements}, value) when is_list(value) do
    if length(elements) != length(value) do
      raise Error.new(:match_error, "List size mismatch")
    end

    Enum.zip(elements, value)
    |> Enum.reduce(%{}, fn {pat, val}, acc ->
      Map.merge(acc, do_match(pat, val))
    end)
  end

  defp do_match({:cons, head, tail}, [value_head | value_tail]) do
    Map.merge(do_match(head, value_head), do_match(tail, value_tail))
  end

  defp do_match(pattern, value) when pattern == value, do: %{}

  defp do_match(_pattern, _value) do
    raise Error.new(:match_error, "Pattern match failed")
  end
end
