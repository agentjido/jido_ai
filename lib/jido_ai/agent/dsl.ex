defmodule Jido.AI.Agent.DSL do
  @moduledoc false

  @spec parse!(Macro.t(), module(), Macro.Env.t()) :: map()
  def parse!(body, target, %Macro.Env{} = caller) do
    config = block!(body, "reasoning", caller)

    case Jido.AI.Agent.Config.normalize(config, target) do
      {:ok, normalized} ->
        normalized

      {:error, reason} ->
        compile_error!(
          caller,
          caller.line,
          "reasoning configuration is invalid for #{inspect(target)}: #{format_reason(reason)}"
        )
    end
  end

  defp block!(body, scope, caller) do
    body
    |> expressions()
    |> Enum.reduce({%{}, MapSet.new()}, fn declaration, {config, names} ->
      {name, value, line} = declaration!(declaration, scope, caller)

      if MapSet.member?(names, name) do
        compile_error!(caller, line, "#{scope} defines #{name} more than once")
      end

      {Map.put(config, name, value), MapSet.put(names, name)}
    end)
    |> elem(0)
  end

  defp declaration!({name, metadata, [[do: body]]}, scope, caller) when is_atom(name) do
    {name, block!(body, "#{scope}.#{name}", caller), metadata[:line]}
  end

  defp declaration!({name, metadata, [value_ast]}, _scope, caller) when is_atom(name) do
    {name, literal!(name, value_ast, metadata[:line], caller), metadata[:line]}
  end

  defp declaration!(declaration, scope, caller) do
    compile_error!(
      caller,
      expression_line(declaration, caller.line),
      "#{scope} accepts only named literal values and nested blocks"
    )
  end

  defp literal!(name, value_ast, line, caller) do
    if Macro.quoted_literal?(value_ast) do
      {value, []} = Code.eval_quoted(value_ast, [], caller)
      portable!(value, name, line, caller)
    else
      compile_error!(caller, line, "#{name} requires a compile-time literal value")
    end
  end

  defp portable!(value, _name, _line, _caller)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
       do: value

  defp portable!([], _name, _line, _caller), do: []

  defp portable!(value, name, line, caller) when is_list(value) do
    if List.improper?(value) do
      compile_error!(caller, line, "#{name} requires portable data")
    end

    if Keyword.keyword?(value) do
      keys = Keyword.keys(value)

      if Enum.uniq(keys) != keys do
        compile_error!(caller, line, "#{name} contains duplicate keys")
      end

      Map.new(value, fn {key, item} -> {key, portable!(item, name, line, caller)} end)
    else
      Enum.map(value, &portable!(&1, name, line, caller))
    end
  end

  defp portable!(value, name, line, caller) when is_map(value) and not is_struct(value) do
    Map.new(value, fn
      {key, item} when is_atom(key) or is_binary(key) ->
        {key, portable!(item, name, line, caller)}

      {_key, _item} ->
        compile_error!(caller, line, "#{name} map keys must be atoms or strings")
    end)
  end

  defp portable!(_value, name, line, caller),
    do: compile_error!(caller, line, "#{name} requires portable data")

  defp format_reason(reason) when is_exception(reason), do: Exception.message(reason)
  defp format_reason(reason), do: inspect(reason, limit: 20, printable_limit: 500)

  defp expressions({:__block__, _metadata, expressions}), do: expressions
  defp expressions(nil), do: []
  defp expressions(expression), do: [expression]

  defp expression_line({_name, metadata, _arguments}, fallback) when is_list(metadata),
    do: Keyword.get(metadata, :line, fallback)

  defp expression_line(_expression, fallback), do: fallback

  defp compile_error!(caller, line, description) do
    raise CompileError,
      file: caller.file,
      line: line || caller.line,
      description: description
  end
end
