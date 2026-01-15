defmodule Jido.AI.Accuracy.Verifiers.DeterministicVerifier do
  @moduledoc """
  Deterministic verifier that compares candidate responses against known ground truth.

  This verifier is useful for scenarios where the correct answer is known
  in advance, such as:
  - Math problems with known solutions
  - Code exercises with expected output
  - Factual questions with single correct answers
  - Unit test result validation

  ## Comparison Types

  ### :exact

  Exact string matching (with optional whitespace normalization).

      verifier = DeterministicVerifier.new!(%{
        ground_truth: "42",
        comparison_type: :exact
      })

  ### :numerical

  Numerical comparison with tolerance for floating-point precision.

      verifier = DeterministicVerifier.new!(%{
        ground_truth: 3.14159,
        comparison_type: :numerical,
        tolerance: 0.001
      })

  ### :regex

  Regular expression pattern matching.

      verifier = DeterministicVerifier.new!(%{
        ground_truth: ~r/\\d{3}-\\d{2}-\\d{4}/,
        comparison_type: :regex
      })

  ## Usage

      # Create verifier
      verifier = DeterministicVerifier.new!(%{
        ground_truth: "42",
        comparison_type: :exact
      })

      # Verify a candidate
      candidate = Candidate.new!(%{content: "The answer is 42"})
      {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})

      # Check result
      result.score  # => 1.0 (match found)
      result.reasoning  # => "Exact match: '42'"

  ## Score Values

  Returns binary scores:
  - `1.0` - Match found (answer is correct)
  - `0.0` - No match (answer is incorrect)

  """

  @behaviour Jido.AI.Accuracy.Verifier

  alias Jido.AI.Accuracy.{Candidate, VerificationResult}

  @type comparison_type :: :exact | :numerical | :regex
  @type t :: %__MODULE__{
          ground_truth: String.t() | number() | Regex.t() | nil,
          comparison_type: comparison_type(),
          tolerance: number() | nil,
          case_sensitive: boolean(),
          normalize_whitespace: boolean()
        }

  defstruct [
    :ground_truth,
    comparison_type: :exact,
    tolerance: nil,
    case_sensitive: false,
    normalize_whitespace: true
  ]

  @doc """
  Creates a new deterministic verifier from the given attributes.

  ## Options

  - `:ground_truth` - The known correct answer (string, number, or regex)
  - `:comparison_type` - Type of comparison (:exact, :numerical, :regex)
  - `:tolerance` - Numerical tolerance for :numerical comparisons
  - `:case_sensitive` - Whether string comparison is case-sensitive
  - `:normalize_whitespace` - Whether to normalize whitespace before comparison

  ## Returns

  - `{:ok, verifier}` - Success
  - `{:error, reason}` - Validation failed

  ## Examples

      iex> DeterministicVerifier.new(%{ground_truth: "42"})
      {:ok, %DeterministicVerifier{ground_truth: "42", comparison_type: :exact}}

      iex> DeterministicVerifier.new(%{ground_truth: 3.14, comparison_type: :numerical})
      {:ok, %DeterministicVerifier{ground_truth: 3.14, comparison_type: :numerical}}

      iex> DeterministicVerifier.new(%{ground_truth: ~r/\\d+/, comparison_type: :regex})
      {:ok, %DeterministicVerifier{ground_truth: ~r/\\d+/, comparison_type: :regex}}

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) do
    verifier = struct(__MODULE__, opts)

    with :ok <- validate_comparison_type(verifier.comparison_type),
         :ok <- validate_tolerance(verifier) do
      {:ok, verifier}
    end
  end

  @doc """
  Creates a new deterministic verifier, raising on error.

  ## Examples

      iex> DeterministicVerifier.new!(%{ground_truth: "42"})
      %DeterministicVerifier{ground_truth: "42", comparison_type: :exact}

  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) do
    case new(opts) do
      {:ok, verifier} -> verifier
      {:error, reason} -> raise ArgumentError, "Invalid deterministic verifier: #{format_error(reason)}"
    end
  end

  @impl true
  @doc """
  Verifies a candidate against the ground truth.

  Returns a binary score (1.0 for match, 0.0 for no match) based on
  the comparison type.

  ## Examples

      iex> verifier = DeterministicVerifier.new!(%{ground_truth: "42"})
      iex> candidate = Candidate.new!(%{content: "42"})
      iex> {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
      iex> result.score
      1.0

  """
  @spec verify(t(), Candidate.t(), map()) :: {:ok, VerificationResult.t()} | {:error, term()}
  def verify(%__MODULE__{} = verifier, %Candidate{} = candidate, _context) do
    answer = extract_answer(candidate.content)
    ground_truth = verifier.ground_truth

    score = compare(verifier, answer, ground_truth)

    reasoning = build_reasoning(verifier, answer, ground_truth, score)

    result = %VerificationResult{
      candidate_id: candidate.id,
      score: score,
      confidence: 1.0,  # Deterministic = 100% confidence
      reasoning: reasoning
    }

    {:ok, result}
  end

  @impl true
  @doc """
  Verifies multiple candidates in batch.

  Each candidate is verified independently against the same ground truth.

  ## Examples

      iex> verifier = DeterministicVerifier.new!(%{ground_truth: "42"})
      iex> candidates = [
      ...>   Candidate.new!(%{id: "1", content: "42"}),
      ...>   Candidate.new!(%{id: "2", content: "43"})
      ...> ]
      iex> {:ok, results} = DeterministicVerifier.verify_batch(verifier, candidates, %{})
      iex> length(results)
      2

  """
  @spec verify_batch(t(), [Candidate.t()], map()) :: {:ok, [VerificationResult.t()]} | {:error, term()}
  def verify_batch(%__MODULE__{} = verifier, candidates, _context) when is_list(candidates) do
    results =
      Enum.map(candidates, fn candidate ->
        {:ok, result} = verify(verifier, candidate, %{})
        result
      end)

    {:ok, results}
  end

  @impl true
  @doc """
  Deterministic verifier does not support streaming.

  """
  @spec supports_streaming?() :: false
  def supports_streaming?, do: false

  # Private functions

  defp compare(%__MODULE__{comparison_type: :exact} = verifier, answer, ground_truth) do
    answer = maybe_normalize_case(verifier, answer, ground_truth)
    answer = maybe_normalize_whitespace(answer, ground_truth)
    ground_truth = maybe_normalize_whitespace(ground_truth, ground_truth)

    if to_string(answer) == to_string(ground_truth), do: 1.0, else: 0.0
  end

  defp compare(%__MODULE__{comparison_type: :numerical, tolerance: tolerance}, answer, ground_truth) do
    answer_num = extract_number(answer)
    truth_num = extract_number(ground_truth)

    if is_number(answer_num) and is_number(truth_num) do
      if abs(answer_num - truth_num) <= tolerance, do: 1.0, else: 0.0
    else
      0.0
    end
  end

  defp compare(%__MODULE__{comparison_type: :regex}, answer, ground_truth) when is_struct(ground_truth, Regex) do
    if Regex.match?(ground_truth, to_string(answer)), do: 1.0, else: 0.0
  end

  defp extract_answer(content) when is_binary(content) do
    content = String.trim(content)

    # Try to extract quoted answer first
    case Regex.run(~r/"([^"]+)"/, content) do
      [_, quoted] -> String.trim(quoted)
      nil -> extract_answer_fallback(content)
    end
  end

  defp extract_answer(_), do: ""

  defp extract_answer_fallback(content) do
    lines = String.split(content, "\n") |> Enum.reject(&(&1 == ""))

    cond do
      # Look for "Answer: X" pattern
      match = Regex.run(~r/Answer:\s*(.+?)(?:\n|\z)/i, content) ->
        String.trim(List.last(match))

      # Look for "Therefore: X" pattern
      match = Regex.run(~r/Therefore:\s*(.+?)(?:\n|\z)/i, content) ->
        String.trim(List.last(match))

      # Look for "Thus: X" pattern
      match = Regex.run(~r/Thus:\s*(.+?)(?:\n|\z)/i, content) ->
        String.trim(List.last(match))

      # Look for "Result: X" pattern
      match = Regex.run(~r/Result:\s*(.+?)(?:\n|\z)/i, content) ->
        String.trim(List.last(match))

      # Look for "The answer is: X" pattern (colon optional)
      match = Regex.run(~r/The answer is:?\s*(.+?)(?:\n|\z)/i, content) ->
        String.trim(List.last(match))

      # Fallback: last line if multiple lines
      length(lines) > 1 -> List.last(lines)
      true -> content
    end
  end

  defp extract_number(value) when is_number(value), do: value

  defp extract_number(value) when is_binary(value) do
    case Float.parse(value) do
      {num, ""} -> num
      {num, _rest} -> num
      :error ->
        case Integer.parse(value) do
          {num, ""} -> num * 1.0
          {num, _rest} -> num * 1.0
          :error -> nil
        end
    end
  end

  defp extract_number(_), do: nil

  defp maybe_normalize_case(%__MODULE__{case_sensitive: true}, answer, _ground_truth) do
    # Case sensitive: don't modify case
    answer
  end

  defp maybe_normalize_case(%__MODULE__{case_sensitive: false}, answer, ground_truth)
       when is_binary(answer) and is_binary(ground_truth) do
    # Case insensitive: if ground_truth is all lowercase, lowercase the answer for comparison
    if ground_truth == String.downcase(ground_truth) do
      String.downcase(answer)
    else
      answer
    end
  end

  defp maybe_normalize_case(%__MODULE__{case_sensitive: false}, answer, _ground_truth), do: answer

  defp maybe_normalize_whitespace(str, _other) when is_binary(str) do
    String.replace(str, ~r/\s+/, " ") |> String.trim()
  end
  defp maybe_normalize_whitespace(val, _other), do: val

  defp build_reasoning(verifier, answer, ground_truth, score) do
    case score do
      1.0 ->
        "Match found using #{verifier.comparison_type} comparison"

      0.0 ->
        "No match: expected '#{inspect(ground_truth)}', got '#{inspect(answer)}'"

      _ ->
        "Comparison result: #{score}"
    end
  end

  # Validation

  defp validate_comparison_type(type) when type in [:exact, :numerical, :regex], do: :ok
  defp validate_comparison_type(_), do: {:error, :invalid_comparison_type}

  defp validate_tolerance(%__MODULE__{comparison_type: :numerical, tolerance: nil}) do
    {:error, :tolerance_required_for_numerical}
  end

  defp validate_tolerance(%__MODULE__{comparison_type: :numerical, tolerance: tol}) when is_number(tol) and tol >= 0 do
    :ok
  end

  defp validate_tolerance(%__MODULE__{comparison_type: :numerical}) do
    {:error, :invalid_tolerance}
  end

  defp validate_tolerance(_), do: :ok
  defp format_error(atom) when is_atom(atom), do: atom
  defp format_error(_), do: :invalid_attributes
end
