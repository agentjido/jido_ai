defmodule JSV.Debanger do
  @moduledoc false
  defmacro __using__(opts) do
    quote do
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
      @__debang_nowrap_records unquote(List.wrap(opts[:records]))
      Module.register_attribute(__MODULE__, :__debang_bang_funs, accumulate: true)
    end
  end

  defmacro debang(call) do
    {:def, meta, [{fun, _, args}]} = call

    quote do
      @__debang_bang_funs {unquote(fun), unquote(meta), unquote(Macro.escape(args)),
                           Module.get_attribute(__MODULE__, :doc_group)}
      unquote(call)
    end
  end

  defmacro __before_compile__(env) do
    bang_funs = Module.get_attribute(env.module, :__debang_bang_funs)
    specs = Module.get_attribute(env.module, :spec)

    quoted_unbanged =
      Enum.map(bang_funs, fn {bang_fun, bang_meta, args, doc_group} ->
        {:spec, {:"::", _, [{^bang_fun, _, arg_types}, return_type]}, _} = find_spec!(specs, bang_fun)

        args_no_defaults = args_no_defaults(args)
        tuple_return_type = return_type_to_tuple_type(return_type)
        nobang_fun = debang_atom(bang_fun)

        quoted =
          quote do
            @doc """
            Same as `#{unquote(bang_fun)}/#{unquote(length(args))}` but rescues
            errors and returns a result tuple.
            """
            @spec unquote(nobang_fun)(unquote_splicing(arg_types)) :: unquote(tuple_return_type)
            if doc_group = unquote(doc_group) do
              @doc group: doc_group
            end

            def unquote(nobang_fun)(unquote_splicing(args)) do
              __debang_wrap__(unquote(bang_fun)(unquote_splicing(args_no_defaults)))
            rescue
              e -> {:error, e}
            end
          end

        Macro.postwalk(quoted, fn
          node -> Macro.update_meta(node, &Keyword.merge(bang_meta, &1))
        end)
      end)

    quote generated: true do
      unquote(quoted_unbanged)

      if @__debang_nowrap_records != [] do
        defp __debang_wrap__(value) when is_tuple(value) and elem(value, 0) in @__debang_nowrap_records do
          {:ok, value}
        end
      end

      defp __debang_wrap__(value) do
        unquote(__MODULE__).__wrap__(value)
      end
    end
  end

  defp find_spec!(specs, bang_fun) do
    spec =
      Enum.find_value(specs, fn
        {:spec, {:"::", _, [{^bang_fun, _, _}, _]}, _} = spec -> spec
        _ -> nil
      end)

    if spec == nil do
      raise "could not debang fun #{inspect(bang_fun)}, no spec found"
    end

    spec
  end

  defp return_type_to_tuple_type(return_type) do
    case return_type do
      {:{}, meta, tuple_vals} ->
        {:|, meta,
         [
           {:{}, meta, [:ok | tuple_vals]},
           {:error,
            quote do
              Exception.t()
            end}
         ]}

      #  2-tuples are not quoted

      {t1, t2} ->
        {:|, [],
         [
           {:{}, [], [:ok, t1, t2]},
           {:error, {{:., [], [:"Elixir.Exception", :t]}, [], []}}
         ]}

      raw_type ->
        {:|, [],
         [
           {:ok, raw_type},
           {:error, {{:., [], [:"Elixir.Exception", :t]}, [], []}}
         ]}
    end
  end

  defp debang_atom(atom) do
    atom
    |> Atom.to_string()
    |> tap(&(true = String.ends_with?(&1, "!")))
    |> String.trim_trailing("!")
    |> String.to_atom()
  end

  defp args_no_defaults(args) do
    Macro.prewalk(args, fn
      {:\\, _, [var, _default]} -> var
      ast -> ast
    end)
  end

  @spec __wrap__(term) :: tuple
  def __wrap__(value) do
    case value do
      {a, b} -> {:ok, a, b}
      {a, b, c} -> {:ok, a, b, c}
      {a, b, c, d} -> {:ok, a, b, c, d}
      {a, b, c, d, e} -> {:ok, a, b, c, d, e}
      v when not is_tuple(v) -> {:ok, v}
    end
  end
end
