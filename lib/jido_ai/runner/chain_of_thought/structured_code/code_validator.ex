defmodule Jido.AI.Runner.ChainOfThought.StructuredCode.CodeValidator do
  @moduledoc """
  Validates generated code against reasoning structure and Elixir best practices.

  Provides:
  - Structure validation comparing code to reasoning plan
  - Style checking with auto-correction suggestions
  - Type checking integration for quality assurance
  - Iterative refinement addressing validation failures

  ## Usage

      {:ok, validation} = CodeValidator.validate(code, reasoning, analysis)

      if validation.valid? do
        # Code is good
      else
        # Get refinement suggestions
        suggestions = validation.suggestions
      end
  """

  require Logger

  @type validation_result :: %{
          valid?: boolean(),
          errors: list(validation_error()),
          warnings: list(validation_warning()),
          suggestions: list(String.t()),
          metrics: map()
        }

  @type validation_error :: %{
          type: atom(),
          message: String.t(),
          line: integer() | nil,
          severity: :error | :warning
        }

  @type validation_warning :: validation_error()

  @doc """
  Validates generated code comprehensively.

  ## Parameters

  - `code` - Generated Elixir code
  - `reasoning` - Structured reasoning used for generation
  - `analysis` - Program analysis
  - `opts` - Options:
    - `:check_syntax` - Validate syntax (default: true)
    - `:check_style` - Validate style (default: true)
    - `:check_structure` - Validate against reasoning (default: true)

  ## Returns

  - `{:ok, validation_result}` - Validation results
  - `{:error, reason}` - Validation failed
  """
  @spec validate(String.t(), map(), map(), keyword()) ::
          {:ok, validation_result()} | {:error, term()}
  def validate(code, reasoning, analysis, opts \\ []) do
    check_syntax = Keyword.get(opts, :check_syntax, true)
    check_style = Keyword.get(opts, :check_style, true)
    check_structure = Keyword.get(opts, :check_structure, true)

    errors = []
    warnings = []
    suggestions = []

    # Syntax validation
    {errors, warnings} =
      if check_syntax do
        case validate_syntax(code) do
          {:ok, syntax_warnings} ->
            {errors, warnings ++ syntax_warnings}

          {:error, syntax_errors} ->
            {errors ++ syntax_errors, warnings}
        end
      else
        {errors, warnings}
      end

    # Style validation
    {warnings, suggestions} =
      if check_style do
        {:ok, style_issues} = validate_style(code)
        style_warnings = Enum.filter(style_issues, &(&1.severity == :warning))
        style_suggestions = Enum.map(style_issues, & &1.message)
        {warnings ++ style_warnings, suggestions ++ style_suggestions}
      else
        {warnings, suggestions}
      end

    # Structure validation
    {errors, warnings, suggestions} =
      if check_structure do
        {:ok, structure_result} = validate_structure(code, reasoning, analysis)

        {errors ++ structure_result.errors, warnings ++ structure_result.warnings,
         suggestions ++ structure_result.suggestions}
      else
        {errors, warnings, suggestions}
      end

    # Calculate metrics
    metrics = calculate_metrics(code, errors, warnings)

    result = %{
      valid?: Enum.empty?(errors),
      errors: errors,
      warnings: warnings,
      suggestions: Enum.uniq(suggestions),
      metrics: metrics
    }

    {:ok, result}
  end

  @doc """
  Validates code syntax using Elixir's Code module.

  ## Parameters

  - `code` - Elixir code string

  ## Returns

  - `{:ok, warnings}` - Syntax is valid
  - `{:error, errors}` - Syntax errors found
  """
  @spec validate_syntax(String.t()) :: {:ok, list()} | {:error, list()}
  def validate_syntax(code) do
    Code.string_to_quoted(code)
    {:ok, []}
  rescue
    e in SyntaxError ->
      error = %{
        type: :syntax_error,
        message: Exception.message(e),
        line: e.line,
        severity: :error
      }

      {:error, [error]}

    e ->
      error = %{
        type: :parse_error,
        message: Exception.message(e),
        line: nil,
        severity: :error
      }

      {:error, [error]}
  end

  @doc """
  Validates code style and idioms.

  ## Parameters

  - `code` - Elixir code string

  ## Returns

  List of style issues
  """
  @spec validate_style(String.t()) :: {:ok, list()} | {:error, term()}
  def validate_style(code) do
    issues = []

    # Check for common style issues
    issues = issues ++ check_line_length(code)
    issues = issues ++ check_naming_conventions(code)
    issues = issues ++ check_module_doc(code)
    issues = issues ++ check_function_doc(code)
    issues = issues ++ check_pipe_usage(code)

    {:ok, issues}
  end

  @doc """
  Validates code structure matches reasoning plan.

  ## Parameters

  - `code` - Generated code
  - `reasoning` - Reasoning structure
  - `analysis` - Program analysis

  ## Returns

  Validation result with structural checks
  """
  @spec validate_structure(String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def validate_structure(code, _reasoning, analysis) do
    errors = []
    warnings = []
    suggestions = []

    # Check if required patterns are present
    {errors, warnings, suggestions} =
      check_required_patterns(code, analysis.elixir_patterns, errors, warnings, suggestions)

    # Check control flow matches analysis
    {errors, warnings, suggestions} =
      check_control_flow(code, analysis.control_flow, errors, warnings, suggestions)

    # Check data transformations match analysis
    {warnings, suggestions} =
      check_data_flow(code, analysis.data_flow, warnings, suggestions)

    result = %{
      errors: errors,
      warnings: warnings,
      suggestions: suggestions
    }

    {:ok, result}
  end

  @doc """
  Generates refinement suggestions for invalid code.

  ## Parameters

  - `validation` - Validation result
  - `code` - Original code
  - `reasoning` - Reasoning structure

  ## Returns

  List of refinement suggestions
  """
  @spec generate_refinement_suggestions(validation_result(), String.t(), map()) ::
          list(String.t())
  def generate_refinement_suggestions(validation, _code, reasoning) do
    suggestions = validation.suggestions

    # Add suggestions based on errors
    error_suggestions =
      Enum.map(validation.errors, fn error ->
        case error.type do
          :syntax_error ->
            "Fix syntax error at line #{error.line}: #{error.message}"

          :missing_pattern ->
            "Add #{error.message} pattern as identified in the reasoning"

          :structure_mismatch ->
            "Restructure code to match the #{reasoning.template_type} template"

          _ ->
            "Address #{error.type}: #{error.message}"
        end
      end)

    # Add suggestions based on warnings
    warning_suggestions =
      Enum.take(validation.warnings, 3)
      |> Enum.map(fn warning ->
        "Consider: #{warning.message}"
      end)

    (suggestions ++ error_suggestions ++ warning_suggestions)
    |> Enum.uniq()
  end

  @doc """
  Attempts to automatically fix common issues.

  ## Parameters

  - `code` - Code with issues
  - `validation` - Validation result

  ## Returns

  - `{:ok, fixed_code}` - Code after fixes
  - `{:error, reason}` - Cannot auto-fix
  """
  @spec auto_fix(String.t(), validation_result()) :: {:ok, String.t()} | {:error, term()}
  def auto_fix(code, validation) do
    # Only attempt auto-fix for style warnings, not errors
    if Enum.any?(validation.errors) do
      {:error, :has_errors}
    else
      # Apply simple fixes
      fixed_code =
        code
        |> fix_trailing_whitespace()
        |> fix_blank_lines()
        |> ensure_final_newline()

      {:ok, fixed_code}
    end
  end

  # Private functions

  defp check_line_length(code) do
    code
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _idx} -> String.length(line) > 120 end)
    |> Enum.map(fn {_line, idx} ->
      %{
        type: :line_too_long,
        message: "Line #{idx} exceeds 120 characters",
        line: idx,
        severity: :warning
      }
    end)
  end

  defp check_naming_conventions(code) do
    issues = []

    # Check for CamelCase in module names
    issues =
      if Regex.match?(~r/defmodule\s+[a-z]/, code) do
        [
          %{
            type: :naming_convention,
            message: "Module names should use CamelCase",
            line: nil,
            severity: :warning
          }
          | issues
        ]
      else
        issues
      end

    # Check for snake_case in function names
    issues =
      if Regex.match?(~r/def\s+[A-Z]/, code) do
        [
          %{
            type: :naming_convention,
            message: "Function names should use snake_case",
            line: nil,
            severity: :warning
          }
          | issues
        ]
      else
        issues
      end

    issues
  end

  defp check_module_doc(code) do
    if String.contains?(code, "defmodule") and not String.contains?(code, "@moduledoc") do
      [
        %{
          type: :missing_documentation,
          message: "Module should have @moduledoc",
          line: nil,
          severity: :warning
        }
      ]
    else
      []
    end
  end

  defp check_function_doc(code) do
    # Simple check: if there's a public function without @doc
    public_fns = Regex.scan(~r/def\s+(\w+)/, code) |> length()
    docs = Regex.scan(~r/@doc/, code) |> length()

    if public_fns > docs do
      [
        %{
          type: :missing_documentation,
          message: "Some public functions missing @doc",
          line: nil,
          severity: :warning
        }
      ]
    else
      []
    end
  end

  defp check_pipe_usage(code) do
    # Check for nested function calls that could use pipe
    if Regex.match?(~r/\w+\(\w+\(\w+\(/, code) and not String.contains?(code, "|>") do
      [
        %{
          type: :style_suggestion,
          message: "Consider using pipe operator for nested function calls",
          line: nil,
          severity: :warning
        }
      ]
    else
      []
    end
  end

  defp check_required_patterns(code, patterns, errors, warnings, suggestions) do
    Enum.reduce(patterns, {errors, warnings, suggestions}, fn pattern, {errs, warns, suggs} ->
      case pattern do
        :pipeline ->
          if String.contains?(code, "|>") do
            {errs, warns, suggs}
          else
            err = %{
              type: :missing_pattern,
              message: "pipeline (|>) operator",
              line: nil,
              severity: :error
            }

            {[err | errs], warns, ["Use pipe operator for data transformations" | suggs]}
          end

        :pattern_matching ->
          if Regex.match?(~r/=\s*%\{|case\s+|def\s+\w+\([^)]*%\{/, code) do
            {errs, warns, suggs}
          else
            warn = %{
              type: :missing_pattern,
              message: "Limited pattern matching usage",
              line: nil,
              severity: :warning
            }

            {errs, [warn | warns], ["Consider using pattern matching" | suggs]}
          end

        :with_syntax ->
          if String.contains?(code, "with ") do
            {errs, warns, suggs}
          else
            sugg = "Consider using 'with' for error handling"
            {errs, warns, [sugg | suggs]}
          end

        _ ->
          {errs, warns, suggs}
      end
    end)
  end

  defp check_control_flow(code, control_flow, errors, warnings, suggestions) do
    case control_flow.type do
      :iterative ->
        if Regex.match?(~r/Enum\.|Stream\.|for\s+/, code) do
          {errors, warnings, suggestions}
        else
          err = %{
            type: :structure_mismatch,
            message: "Expected iterative control flow (Enum/Stream/for)",
            line: nil,
            severity: :error
          }

          {[err | errors], warnings, suggestions}
        end

      :conditional ->
        if Regex.match?(~r/case\s+|cond\s+|if\s+|def\s+\w+.*when/, code) do
          {errors, warnings, suggestions}
        else
          err = %{
            type: :structure_mismatch,
            message: "Expected conditional logic (case/cond/if/guards)",
            line: nil,
            severity: :error
          }

          {[err | errors], warnings, suggestions}
        end

      :recursive ->
        # Check for recursive calls
        {errors, warnings, suggestions}

      _ ->
        {errors, warnings, suggestions}
    end
  end

  defp check_data_flow(code, data_flow, warnings, suggestions) do
    # Check if expected transformations are present
    Enum.reduce(data_flow.transformations, {warnings, suggestions}, fn transform,
                                                                       {warns, suggs} ->
      present =
        case transform do
          :map -> Regex.match?(~r/Enum\.map|Stream\.map/, code)
          :filter -> Regex.match?(~r/Enum\.filter|Enum\.reject|Stream\.filter/, code)
          :reduce -> Regex.match?(~r/Enum\.reduce|Enum\.sum/, code)
          :sort -> Regex.match?(~r/Enum\.sort/, code)
          :group -> Regex.match?(~r/Enum\.group_by/, code)
          _ -> true
        end

      if present do
        {warns, suggs}
      else
        warn = %{
          type: :data_flow_mismatch,
          message: "Expected #{transform} transformation",
          line: nil,
          severity: :warning
        }

        sugg = "Consider adding #{transform} operation as identified in analysis"
        {[warn | warns], [sugg | suggs]}
      end
    end)
  end

  defp calculate_metrics(code, errors, warnings) do
    lines = String.split(code, "\n")
    line_count = length(lines)

    # Count non-blank lines
    code_lines = Enum.count(lines, &(String.trim(&1) != ""))

    # Count functions
    function_count = Regex.scan(~r/def\s+\w+/, code) |> length()

    # Calculate average function size
    avg_function_size =
      if function_count > 0, do: div(code_lines, function_count), else: code_lines

    %{
      total_lines: line_count,
      code_lines: code_lines,
      function_count: function_count,
      avg_function_size: avg_function_size,
      error_count: length(errors),
      warning_count: length(warnings),
      complexity: estimate_complexity(code)
    }
  end

  defp estimate_complexity(code) do
    # Simple complexity estimation based on control flow keywords
    complexity_keywords = [
      "case ",
      "cond ",
      "if ",
      "when ",
      "unless ",
      "for ",
      "Enum.",
      "Stream."
    ]

    count =
      Enum.reduce(complexity_keywords, 0, fn keyword, acc ->
        acc + (Regex.scan(~r/#{keyword}/, code) |> length())
      end)

    cond do
      count <= 3 -> :low
      count <= 8 -> :moderate
      count <= 15 -> :high
      true -> :very_high
    end
  end

  defp fix_trailing_whitespace(code) do
    code
    |> String.split("\n")
    |> Enum.map_join("\n", &String.trim_trailing/1)
  end

  defp fix_blank_lines(code) do
    # Remove excessive blank lines (more than 2 consecutive)
    Regex.replace(~r/\n{4,}/, code, "\n\n\n")
  end

  defp ensure_final_newline(code) do
    if String.ends_with?(code, "\n") do
      code
    else
      code <> "\n"
    end
  end
end
