defmodule Jido.AI.Runner.GEPA.Evaluation.Validators.CodeValidator do
  @moduledoc """
  Code validation utilities for GEPA code evaluation.

  Provides syntax validation for various programming languages:
  - Elixir: Uses Code.string_to_quoted/2
  - Python: Placeholder (TODO)
  - JavaScript: Placeholder (TODO)

  ## Usage

      # Validate Elixir syntax
      result = CodeValidator.validate_elixir_syntax(~S'''
      defmodule Example do
        def hello, do: "world"
      end
      ''')

      result.valid  # => true
      result.errors # => []

      # Invalid syntax
      result = CodeValidator.validate_elixir_syntax("def broken")
      result.valid  # => false
      result.errors # => [%{type: :syntax_error, message: "..."}]
  """

  require Logger

  @type validation_result :: %{
          valid: boolean(),
          errors: list(map())
        }

  @doc """
  Validates Elixir code syntax.

  Uses `Code.string_to_quoted/2` to parse the code and detect syntax errors.

  ## Examples

      iex> CodeValidator.validate_elixir_syntax("def hello, do: :world")
      %{valid: true, errors: []}

      iex> result = CodeValidator.validate_elixir_syntax("def broken")
      iex> result.valid
      false

      iex> result = CodeValidator.validate_elixir_syntax("defmodule Test do\\nend")
      iex> result.valid
      true
  """
  @spec validate_elixir_syntax(String.t()) :: validation_result()
  def validate_elixir_syntax(code) when is_binary(code) do
    case Code.string_to_quoted(code) do
      {:ok, _ast} ->
        %{valid: true, errors: []}

      {:error, {line, error_info, token}} ->
        error_message = format_elixir_error(error_info, token)

        Logger.debug("Elixir syntax error at line #{line}: #{error_message}")

        %{
          valid: false,
          errors: [
            %{
              type: :syntax_error,
              line: line,
              message: error_message,
              token: token
            }
          ]
        }
    end
  end

  @doc """
  Validates Python code syntax.

  TODO: Implement Python syntax validation using AST parsing or external tool.

  For now, returns a placeholder result.
  """
  @spec validate_python_syntax(String.t()) :: validation_result()
  def validate_python_syntax(_code) do
    Logger.debug("Python syntax validation not yet implemented")

    # Placeholder: always valid
    %{valid: true, errors: []}
  end

  @doc """
  Validates JavaScript code syntax.

  TODO: Implement JavaScript syntax validation.

  For now, returns a placeholder result.
  """
  @spec validate_javascript_syntax(String.t()) :: validation_result()
  def validate_javascript_syntax(_code) do
    Logger.debug("JavaScript syntax validation not yet implemented")

    # Placeholder: always valid
    %{valid: true, errors: []}
  end

  @doc """
  Generic code validation dispatcher.

  Dispatches to language-specific validator based on language atom.

  ## Examples

      CodeValidator.validate_code("def hello", :elixir)
      CodeValidator.validate_code("print('hello')", :python)
  """
  @spec validate_code(String.t(), atom()) :: validation_result()
  def validate_code(code, language) when is_binary(code) do
    case language do
      :elixir -> validate_elixir_syntax(code)
      :python -> validate_python_syntax(code)
      :javascript -> validate_javascript_syntax(code)
      _ -> %{valid: true, errors: []}
    end
  end

  # Private Functions

  @doc false
  @spec format_elixir_error(String.t() | {module(), binary()}, term()) :: String.t()
  defp format_elixir_error(error_info, token) when is_binary(error_info) do
    "#{error_info} (#{inspect(token)})"
  end

  defp format_elixir_error({module, message}, token) when is_atom(module) do
    "#{module}: #{message} (#{inspect(token)})"
  end

  defp format_elixir_error(error_info, _token) do
    inspect(error_info)
  end
end
