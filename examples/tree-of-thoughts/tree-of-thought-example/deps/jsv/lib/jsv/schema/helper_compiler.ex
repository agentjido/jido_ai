defmodule JSV.Schema.HelperCompiler do
  alias JSV.Schema

  @moduledoc false

  defguard is_literal(v) when is_atom(v) or is_integer(v) or (is_tuple(v) and is_list(elem(v, 2)))

  defp extract_guard(args_or_guarded) do
    case args_or_guarded do
      {:when, _meta, [args, guard]} -> {guard, args}
      args -> {true, args}
    end
  end

  defp expand_args(args, env) do
    Enum.map(args, fn {prop, value} ->
      value = Macro.expand(value, env)

      if Macro.quoted_literal?(value) do
        {:const, prop, value}
      else
        expand_expression(prop, value)
      end
    end)
  end

  defp expand_expression(prop, value) do
    case value do
      {:<-, _, [expr, value]} ->
        {bind, typespec} = extract_typespec(value)
        {:var, prop, bind, typespec, expr}

      {{:., _, _}, _, _} = remote_call ->
        {:call, prop, remote_call}

      value ->
        {bind, typespec} = extract_typespec(value)
        {:var, prop, bind, typespec, bind}
    end
  end

  defp extract_typespec(value) do
    case value do
      {:"::", _, [bind, typespec]} -> {bind, typespec}
      bind -> {bind, {:term, [], nil}}
    end
  end

  defp prepare_fun(args) do
    schema_props =
      Enum.map(args, fn
        {:const, prop, const} -> {prop, const}
        {:var, prop, _bind, _typespec, expr} -> {prop, expr}
        {:call, prop, call} -> {prop, call}
      end)

    bindings =
      Enum.flat_map(args, fn
        {:const, _prop, _const} -> []
        {:var, _prop, bind, _typespec, _expr} -> [bind]
        {:call, _, _} -> []
      end)

    typespecs =
      Enum.flat_map(args, fn
        {:const, _prop, _const} -> []
        {:var, _prop, _bind, typespec, _expr} -> [typespec]
        {:call, _, _} -> []
      end)

    doc_bindings =
      Enum.map(args, fn
        {:const, prop, const} -> {prop, inspect(const)}
        {:var, prop, bind, _typespec, _expr} -> {:var, {prop, Macro.to_string(bind)}}
        {:call, prop, call} -> {prop, Macro.to_string(call)}
      end)

    {schema_props, bindings, typespecs, doc_bindings}
  end

  defmacro defcompose(fun, args_or_guarded) do
    {guard, args} = extract_guard(args_or_guarded)

    args = expand_args(args, __CALLER__)
    {schema_props, bindings, typespecs, doc_bindings} = prepare_fun(args)

    # Start of quote

    quote location: :keep do
      doc_custom =
        case Module.get_attribute(__MODULE__, :doc) do
          {_, text} when is_binary(text) -> ["\n\n", text]
          _ -> ""
        end

      doc_schema_props =
        unquote(doc_bindings)
        |> Enum.map(fn
          {:var, {prop, varname}} -> "`#{prop}: #{varname}`"
          {prop, value_or_call} -> "`#{prop}: #{value_or_call}`"
        end)
        |> :lists.reverse()
        |> case do
          [last | [_ | _] = prev] ->
            prev
            |> Enum.intersperse(", ")
            |> :lists.reverse([" and ", last])

          [single] ->
            [single]
        end

      @doc """
      Defines or merges onto a JSON Schema with #{doc_schema_props}.#{doc_custom}
      """
      @spec unquote(fun)(Schema.merge_base(), unquote_splicing(typespecs)) :: Schema.schema()
      def unquote(fun)(merge_base \\ nil, unquote_splicing(bindings)) when unquote(guard) do
        Schema.merge(merge_base, unquote(schema_props))
      end
    end
  end

  defmacro defcompose_deprecated(fun, arity) do
    args = Macro.generate_arguments(arity, __MODULE__)

    quote do
      if Mix.env() != :test do
        @deprecated "Use `JSV.Schema.Composer.#{unquote(fun)}/#{unquote(arity) + 1}`. " <>
                      "More information: https://hexdocs.pm/jsv/api-changes-v0-9.html"
      end

      @doc false
      def unquote(fun)(base \\ nil, unquote_splicing(args)) do
        JSV.Schema.Composer.unquote(fun)(base, unquote_splicing(args))
      end
    end
  end

  defmacro defpreset(fun, args_or_guarded) do
    {guard, args} = extract_guard(args_or_guarded)

    args = expand_args(args, __CALLER__)
    {schema_props, bindings, typespecs, doc_bindings} = prepare_fun(args)

    # Start of quote

    quote location: :keep do
      doc_custom =
        case Module.get_attribute(__MODULE__, :doc) do
          {_, text} when is_binary(text) -> ["\n\n", text]
          _ -> ""
        end

      doc_schema_props =
        unquote(doc_bindings)
        |> Enum.map(fn
          {:var, {prop, varname}} -> "`#{prop}: #{varname}`"
          {prop, value_or_call} -> "`#{prop}: #{value_or_call}`"
        end)
        |> :lists.reverse()
        |> case do
          [last | [_ | _] = prev] ->
            prev
            |> Enum.intersperse(", ")
            |> :lists.reverse([" and ", last])

          [single] ->
            [single]
        end

      @doc """
      Returns a JSON Schema with #{doc_schema_props}.#{doc_custom}
      """
      @doc group: "Schema Presets"
      @spec unquote(fun)(unquote_splicing(typespecs), Schema.attributes() | nil) :: Schema.schema()
      def unquote(fun)(unquote_splicing(bindings), extra \\ nil) when unquote(guard) do
        case extra do
          nil -> Map.new(unquote(schema_props))
          _ -> Schema.combine(extra, unquote(schema_props))
        end
      end
    end
  end
end
