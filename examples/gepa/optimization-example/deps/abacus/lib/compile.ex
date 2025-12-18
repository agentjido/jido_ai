defmodule Abacus.Compile do
  def post_compile(ast, _lookup) do
    ast
    |> add_use_bitwise()
    |> Macro.prewalk(&prepare_variables/1)
    |> Macro.prewalk(&replace_operators/1)
    |> Macro.prewalk(&prepare_fn_calls/1)
    |> Macro.prewalk(&inject_comparison/1)
  end

  @bitwise_ops ~w[&&& ||| ^^^ ~~~ <<< >>>]a

  def add_use_bitwise(ast) do
    {_, contains_bitwise} = Macro.prewalk(ast, false, fn
      {op, _, _}, false = ast when op in @bitwise_ops -> {ast, true}
      ast, true -> {ast, true}
      ast, false -> {ast, false}
    end)

    case contains_bitwise do
      true ->
        quote do
          import Bitwise
          unquote(ast)
        end
      false ->
        ast
    end
  end

  def prepare_variables({:., ctx, [lhs, {:variable, name}]}) do
    put_get_in(ctx, [prepare_variables(lhs), name])
  end
  def prepare_variables({:., _, [_, :get_in]} = ast) do
    ast
  end
  def prepare_variables({:., ctx, [lhs, expr]}) do
    put_get_in(ctx, [lhs, expr])
  end
  def prepare_variables(diff) do
    diff
  end

  def mfa(module, function, args) do
    module =
      module
      |> Module.split()
      |> Enum.map(&String.to_atom/1)

    {{:., [],
      [{:__aliases__, [alias: false], module}, function]}, [], args}
  end

  def put_get_in(ctx, args) do
    {{:., [],
      [{:__aliases__, [alias: false], [:Abacus, :Runtime, :Scope]}, :get_in]}, ctx, args}
  end

  def replace_operators({:^, _ctx, [lhs, rhs]}) do
    quote do
      :math.pow(unquote(lhs), unquote(rhs))
    end
  end
  def replace_operators({:!, _ctx, [expr]}) do
    quote do
      Abacus.Runtime.Helpers.factorial(unquote(expr))
    end
  end
  def replace_operators(diff) do
    diff
  end

  def prepare_fn_calls({{var, _, nil} = variable, ctx, args} = ast) when is_list(args) and is_atom(var) do
    if var |> to_string |> String.starts_with?("var") do
      {{:., ctx, [variable]}, ctx, args}
    else
      ast
    end
  end
  def prepare_fn_calls(diff) do
    diff
  end

  @compare_ops ~w[== != >= <= > <]a

  def inject_comparison({op, _ctx, args}) when op in @compare_ops do
    args = Enum.map(args, &mfa(Abacus.Runtime.Helpers, :cast_for_comparison, [&1]))
    mfa(Abacus.Runtime.Helpers, :compare, [op | args])
  end
  def inject_comparison(ast) do
    ast
  end
end
