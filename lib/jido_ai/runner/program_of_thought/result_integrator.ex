defmodule Jido.AI.Runner.ProgramOfThought.ResultIntegrator do
  @moduledoc """
  Integrates computational results back into reasoning flow.

  Responsibilities:
  - Format results clearly
  - Generate explanations of computational steps
  - Validate result plausibility
  - Track multi-step computations

  ## Result Format

  Returns structured results with:
  - `answer`: The final computed value
  - `explanation`: Natural language description of steps
  - `steps`: List of computational steps taken
  - `validation`: Plausibility check results

  ## Example

      iex> execution_result = %{result: 360, duration_ms: 10, output: ""}
      iex> ResultIntegrator.integrate(execution_result, opts)
      {:ok, %{
        answer: 360,
        explanation: "Calculated 15% of 240 by multiplying 240 by 0.15...",
        steps: [...],
        validation: %{is_plausible: true, confidence: 0.95}
      }}
  """

  require Logger

  alias Jido.AI.Actions.ReqLlm.ChatCompletion

  @doc """
  Integrates execution result with explanation and validation.

  ## Options

  - `:program` - The executed program code
  - `:analysis` - Problem analysis from classifier
  - `:generate_explanation` - Whether to generate explanation (default: true)
  - `:validate_result` - Whether to validate result (default: true)
  - `:model` - LLM model for explanation generation
  - `:context` - Agent context
  """
  @spec integrate(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def integrate(execution_result, opts \\ []) do
    program = Keyword.get(opts, :program)
    analysis = Keyword.get(opts, :analysis)
    generate_explanation = Keyword.get(opts, :generate_explanation, true)
    validate_result = Keyword.get(opts, :validate_result, true)
    model = Keyword.get(opts, :model)
    context = Keyword.get(opts, :context, %{})

    result = %{
      answer: execution_result.result,
      explanation: nil,
      steps: [],
      validation: nil
    }

    # Extract computational steps from program
    result = Map.put(result, :steps, extract_steps(program))

    # Generate explanation if requested
    result =
      if generate_explanation do
        case generate_explanation(execution_result, program, analysis, model, context) do
          {:ok, explanation} ->
            Map.put(result, :explanation, explanation)

          {:error, reason} ->
            Logger.warning("Explanation generation failed: #{inspect(reason)}")
            Map.put(result, :explanation, "Computation completed successfully.")
        end
      else
        result
      end

    # Validate result if requested
    result =
      if validate_result do
        validation = validate_plausibility(execution_result, program, analysis)
        Map.put(result, :validation, validation)
      else
        result
      end

    {:ok, result}
  end

  # Private functions

  defp extract_steps(program) when is_binary(program) do
    # Extract comments and assignments from program
    lines =
      program
      |> String.split("\n")
      |> Enum.with_index(1)

    steps =
      Enum.reduce(lines, [], fn {line, line_num}, acc ->
        cond do
          # Extract step comments
          Regex.match?(~r/^\s*#\s*Step\s+\d+:/, line) ->
            step = String.trim(line) |> String.replace(~r/^\s*#\s*/, "")
            [{:comment, line_num, step} | acc]

          # Extract calculations
          Regex.match?(~r/\s*\w+\s*=.*[\+\-\*\/]/, line) ->
            calculation = String.trim(line)
            [{:calculation, line_num, calculation} | acc]

          true ->
            acc
        end
      end)

    Enum.reverse(steps)
  end

  defp extract_steps(_), do: []

  defp generate_explanation(execution_result, program, analysis, model, context) do
    domain = analysis.domain
    result = execution_result.result

    prompt = build_explanation_prompt(program, result, domain)

    case call_llm(prompt, model, context) do
      {:ok, explanation} ->
        {:ok, String.trim(explanation)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_explanation_prompt(program, result, domain) do
    """
    Explain the computational steps performed in the following program.

    ## Program
    ```elixir
    #{program}
    ```

    ## Result
    #{format_result(result)}

    ## Domain
    #{domain}

    Generate a clear, concise explanation of:
    1. What calculations were performed
    2. Why each step was necessary
    3. How the final answer was obtained

    Write the explanation in natural language that a person without programming
    knowledge could understand. Focus on the mathematical/computational logic,
    not the code syntax.

    Keep the explanation to 2-3 sentences maximum.
    """
  end

  defp format_result(result) when is_number(result) do
    if is_float(result) do
      Float.round(result, 4)
    else
      result
    end
    |> inspect()
  end

  defp format_result(result), do: inspect(result)

  defp validate_plausibility(execution_result, _program, analysis) do
    result = execution_result.result

    checks = [
      check_result_type(result, analysis),
      check_result_magnitude(result, analysis),
      check_execution_time(execution_result.duration_ms, analysis)
    ]

    passed_checks = Enum.count(checks, fn {passed, _} -> passed end)
    total_checks = length(checks)

    is_plausible = passed_checks >= div(total_checks, 2) + 1
    confidence = passed_checks / total_checks

    %{
      is_plausible: is_plausible,
      confidence: confidence,
      checks: checks
    }
  end

  defp check_result_type(result, analysis) do
    # Check if result type matches expected for domain
    expected_numeric = analysis.domain in [:mathematical, :financial, :scientific]

    if expected_numeric do
      {is_number(result), "Result type matches domain expectations"}
    else
      {true, "No type constraints for domain"}
    end
  end

  defp check_result_magnitude(result, analysis) when is_number(result) do
    # Check if magnitude is reasonable
    # For example, percentages should be 0-100, prices shouldn't be negative, etc.

    reasonable =
      cond do
        analysis.domain == :financial and result < 0 ->
          false

        :percentage in analysis.operations and (result < 0 or result > 100) ->
          false

        abs(result) > 1.0e15 ->
          # Suspiciously large
          false

        true ->
          true
      end

    {reasonable, "Result magnitude is reasonable"}
  end

  defp check_result_magnitude(_, _) do
    {true, "Non-numeric result, no magnitude check"}
  end

  defp check_execution_time(duration_ms, analysis) do
    # Simple problems should execute quickly
    expected_max = expected_duration(analysis.complexity)

    if duration_ms <= expected_max do
      {true, "Execution time within expected range"}
    else
      {false, "Execution took longer than expected"}
    end
  end

  defp expected_duration(:low), do: 100
  defp expected_duration(:medium), do: 500
  defp expected_duration(:high), do: 2000

  defp call_llm(prompt, model_name, context) do
    model = model_name || get_default_model(context)

    params = %{
      model: model,
      messages: [
        %{role: "system", content: system_message()},
        %{role: "user", content: prompt}
      ],
      temperature: 0.3,
      max_tokens: 500
    }

    try do
      case ChatCompletion.run(params, context) do
        {:ok, result, _context} ->
          content = extract_content(result)
          {:ok, content}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        {:error, {:llm_error, error}}
    end
  end

  defp system_message do
    """
    You are an expert at explaining computational processes in clear, simple language.

    Your explanations should:
    - Be concise (2-3 sentences maximum)
    - Focus on the logic, not the code
    - Be understandable to non-programmers
    - Highlight key calculations and their purpose
    """
  end

  defp extract_content(result) do
    case result do
      %{content: content} -> content
      %{message: %{content: content}} -> content
      %{choices: [%{message: %{content: content}} | _]} -> content
      _ -> inspect(result)
    end
  end

  defp get_default_model(context) do
    Map.get(context, :default_model, "gpt-4")
  end
end
