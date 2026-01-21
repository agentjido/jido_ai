defmodule Jido.AI.Runner.ChainOfThought.OutcomeValidator do
  @moduledoc """
  Validates execution outcomes against reasoning predictions.

  This module compares actual execution results with expected outcomes from
  the reasoning plan, detecting unexpected results and potential issues.
  """

  require Logger

  alias Jido.AI.Runner.ChainOfThought.ReasoningParser.ReasoningStep

  use TypedStruct

  typedstruct module: ValidationResult do
    @moduledoc """
    Result of outcome validation.

    Contains information about whether the outcome matched expectations,
    along with details about any discrepancies.
    """

    field(:matches_expectation, boolean(), default: true)
    field(:expected_outcome, String.t())
    field(:actual_outcome, String.t())
    field(:confidence, float(), default: 1.0)
    field(:notes, list(String.t()), default: [])
  end

  @doc """
  Validates an execution result against a reasoning step's expected outcome.

  Performs basic validation by checking if the result indicates success
  and optionally comparing with the expected outcome text.

  ## Parameters

  - `result` - The execution result (typically `{:ok, data}` or `{:error, reason}`)
  - `step` - The reasoning step containing expected outcome
  - `opts` - Optional validation options

  ## Returns

  A `%ValidationResult{}` struct with validation details.

  ## Options

  - `:strict` - Whether to perform strict text matching (default: false)
  - `:log_discrepancies` - Whether to log validation failures (default: true)

  ## Examples

      iex> step = %ReasoningStep{expected_outcome: "Data validated successfully"}
      iex> result = {:ok, %{status: :validated}}
      iex> validation = OutcomeValidator.validate(result, step)
      iex> validation.matches_expectation
      true
  """
  @spec validate(term(), ReasoningStep.t(), keyword()) :: ValidationResult.t()
  def validate(result, %ReasoningStep{} = step, opts \\ []) do
    expected = step.expected_outcome || ""
    actual = format_result(result)

    matches = check_match(result, expected, opts)
    confidence = calculate_confidence(result, expected)
    notes = build_notes(result, expected, matches)

    validation = %ValidationResult{
      matches_expectation: matches,
      expected_outcome: expected,
      actual_outcome: actual,
      confidence: confidence,
      notes: notes
    }

    if Keyword.get(opts, :log_discrepancies, true) and not matches do
      log_validation_failure(validation, step)
    end

    validation
  end

  @doc """
  Validates that a result indicates success.

  This is a simpler validation that just checks if the result
  is an `:ok` tuple or truthy value.

  ## Parameters

  - `result` - The execution result

  ## Returns

  Boolean indicating if the result represents success.
  """
  @spec successful?(term()) :: boolean()
  def successful?({:ok, _}), do: true
  def successful?(:ok), do: true
  def successful?({:error, _}), do: false
  def successful?(:error), do: false
  def successful?(true), do: true
  def successful?(false), do: false
  # Assume success if not explicitly error
  def successful?(_), do: true

  @doc """
  Checks if a validation result indicates an unexpected outcome.

  ## Parameters

  - `validation` - A ValidationResult struct

  ## Returns

  Boolean indicating if the outcome was unexpected.
  """
  @spec unexpected_outcome?(ValidationResult.t()) :: boolean()
  def unexpected_outcome?(%ValidationResult{matches_expectation: false}), do: true
  def unexpected_outcome?(%ValidationResult{confidence: conf}) when conf < 0.5, do: true
  def unexpected_outcome?(_), do: false

  # Private helper functions

  defp format_result({:ok, data}) when is_map(data) do
    data
    |> inspect(limit: 100)
    |> String.slice(0, 200)
  end

  defp format_result({:ok, data}), do: "Success: #{inspect(data, limit: 50)}"
  defp format_result({:error, reason}), do: "Error: #{inspect(reason, limit: 100)}"
  defp format_result(other), do: inspect(other, limit: 100)

  defp check_match({:ok, _}, _expected, _opts), do: true
  defp check_match({:error, _}, _expected, _opts), do: false

  defp check_match(result, expected, opts) do
    if Keyword.get(opts, :strict, false) and expected != "" do
      result_str = format_result(result)
      String.contains?(String.downcase(result_str), String.downcase(expected))
    else
      # Non-strict: just check for success
      successful?(result)
    end
  end

  defp calculate_confidence({:ok, _}, _expected), do: 1.0
  defp calculate_confidence({:error, _}, _expected), do: 0.0
  # No expectation to compare against
  defp calculate_confidence(_, ""), do: 0.8
  # Has expectation, non-error result
  defp calculate_confidence(_, _), do: 0.9

  defp build_notes(result, expected, matches) do
    notes = []

    notes =
      if expected == "" do
        ["No expected outcome specified in reasoning plan" | notes]
      else
        notes
      end

    notes =
      if matches do
        notes
      else
        case result do
          {:error, reason} ->
            ["Execution failed: #{inspect(reason)}" | notes]

          _ ->
            ["Result did not match expected outcome" | notes]
        end
      end

    Enum.reverse(notes)
  end

  defp log_validation_failure(validation, step) do
    Logger.warning("""
    Outcome validation failure:
      Step: #{step.description}
      Expected: #{validation.expected_outcome}
      Actual: #{validation.actual_outcome}
      Confidence: #{validation.confidence}
      Notes: #{Enum.join(validation.notes, ", ")}
    """)
  end
end
