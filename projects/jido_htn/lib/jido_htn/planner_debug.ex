defmodule Jido.HTN.Debug do
  @moduledoc false
  def format_debug_tree(tree, indent \\ 0)

  def format_debug_tree({:compound, name, success, children}, indent) do
    prefix = String.duplicate("  ", indent)
    status = if success, do: "+", else: "-"
    result = ["#{prefix}#{status} compound: #{name}"]

    child_results =
      Enum.flat_map(children, fn child ->
        format_debug_tree(child, indent + 1)
      end)

    result ++ child_results
  end

  def format_debug_tree({:primitive, name, success, condition_results}, indent) do
    prefix = String.duplicate("  ", indent)
    status = if success, do: "+", else: "-"
    result = ["#{prefix}#{status} primitive: #{name}"]

    condition_lines =
      Enum.map(condition_results, fn {name, result} ->
        condition_status = if result, do: "+", else: "-"
        "#{prefix}  #{condition_status} #{name}"
      end)

    result ++ condition_lines
  end

  def format_debug_tree({success, method_name, condition_results, subtree}, indent) do
    prefix = String.duplicate("  ", indent)
    status = if success, do: "+", else: "-"
    method_line = ["#{prefix}#{status} #{method_name}"]

    condition_lines =
      Enum.map(condition_results, fn
        {name, result} when is_binary(name) ->
          condition_status = if result, do: "+", else: "-"
          "#{prefix}  #{condition_status} #{name}"

        {{module, func, arity}, result} ->
          condition_status = if result, do: "+", else: "-"
          "#{prefix}  #{condition_status} #{module}.#{func}/#{arity}"

        other ->
          "#{prefix}  ? Unknown condition: #{inspect(other)}"
      end)

    subtree_output = format_debug_tree(subtree, indent + 1)
    method_line ++ condition_lines ++ subtree_output
  end

  def format_debug_tree({:empty, _, _}, _indent), do: []

  def format_debug_tree(other, indent) do
    prefix = String.duplicate("  ", indent)
    ["#{prefix}? Unknown: #{inspect(other)}"]
  end

  @doc """
  Converts the debug tree list into a single, formatted string.
  """
  def tree_to_string(tree_list) do
    Enum.join(tree_list, "\n")
  end
end
