defmodule Abacus do
  @moduledoc """
  A math-expression parser, evaluator and formatter for Elixir.

  ## Features

  ### Supported operators

   - `+`, `-`, `/`, `*`
   - Exponentials with `^`
   - Factorial (`n!`)
   - Bitwise operators
     * `<<` `>>` bitshift
     * `&` bitwise and
     * `|` bitwise or
     * `|^` bitwise xor
     * `~` bitwise not (unary)
   - Boolean operators
     * `&&`, `||`, `not`
     * `==`, `!=`, `>`, `>=`, `<`, `<=`
     * Ternary `condition ? if_true : if_false`

  ### Supported functions

   - `sin(x)`, `cos(x)`, `tan(x)`
   - `round(n, precision = 0)`, `ceil(n, precision = 0)`, `floor(n, precision = 0)`

  ### Reserved words

   - `true`
   - `false`
   - `null`

  ### Access to variables in scope

   - `a` with scope `%{"a" => 10}` would evaluate to `10`
   - `a.b` with scope `%{"a" => %{"b" => 42}}` would evaluate to `42`
   - `list[2]` with scope `%{"list" => [1, 2, 3]}` would evaluate to `3`

  ### Data types

   - Boolean: `true`, `false`
   - None: `null`
   - Integer: `0`, `40`, `-184`
   - Float: `0.2`, `12.`, `.12`
   - String: `"Hello World"`, `"He said: \"Let's write a math parser\""`

  If a variable is not in the scope, `eval/2` will result in `{:error, error}`.
  """

  @doc """
  Evaluates the given expression with no scope.

  If `expr` is a string, it will be parsed first.
  """
  @spec eval(expr::tuple | charlist | String.t) :: {:ok, result::number} | {:error, error::map}
  @spec eval(expr::tuple | charlist | String.t, scope::map) :: {:ok, result::number} | {:error, error::map}

  @spec eval!(expr::tuple | charlist | String.t) :: result::number
  @spec eval!(expr::tuple | charlist | String.t, scope::map) :: result::number
  def eval(source, scope \\ [], vars \\ %{})
  def eval(source, scope, _vars) when is_binary(source) or is_bitstring(source) do
    with {:ok, ast, vars} <- compile(source) do
      eval(ast, scope, vars)
    end
  end

  def eval(expr, scope, vars) do
    scope = Abacus.Runtime.Scope.prepare_scope(scope, vars)
    try do
       case Code.eval_quoted(expr, scope) do
        {result, _} -> {:ok, result}
      end
    rescue
      e -> {:error, e}
    catch
      e -> {:error, e}
    end
  end

  @doc """
  Evaluates the given expression.

  Raises errors when parsing or evaluating goes wrong.
  """
  def eval!(expr) do
    eval!(expr, %{})
  end

  @doc """
  Evaluates the given expression with the given scope.

  If `expr` is a string, it will be parsed first.
  """

  def eval!(expr, scope) do
    case Abacus.eval(expr, scope) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  def compile(source) when is_binary(source) do
    source
    |> String.to_charlist()
    |> compile()
  end
  def compile(source) when is_list(source) do
    with _ = Process.put(:variables, %{}),
        {:ok, tokens, _} <- :math_term.string(source),
        {:ok, ast} <- :new_parser.parse(tokens) do
          vars = Process.get(:variables)
          ast = Abacus.Compile.post_compile(ast, vars)
          Process.delete(:variables)
          {:ok, ast, vars}
    end
  end

  @spec format(expr :: tuple | String.t | charlist) :: {:ok, String.t} | {:error, error::map}
  @doc """
  Pretty-prints the given expression.

  If `expr` is a string, it will be parsed first.
  """
  def format(expr) when is_binary(expr) or is_bitstring(expr) do
    case compile(expr) do
      {:ok, expr, _vars} ->
        format(expr)
      {:error, _} = error -> error
    end
  end

  def format(expr) do
    try do
      {:ok, Abacus.Format.format(expr)}
    rescue
      error -> {:error, error}
    end
  end
end
