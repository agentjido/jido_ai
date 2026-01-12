defmodule Jido.AI.Accuracy.CritiqueResult do
  @moduledoc """
  Result type for critique operations.

  Contains structured feedback about a candidate response,
  including identified issues, suggestions, and severity scores.

  ## Fields

  - `:issues` - List of identified issues (strings or maps)
  - `:suggestions` - List of improvement suggestions
  - `:severity` - Overall severity score (0.0 to 1.0)
  - `:feedback` - Natural language feedback summary
  - `:actionable` - Whether issues are actionable
  - `:metadata` - Additional metadata

  ## Severity Levels

  - **Low (0.0-0.3)**: Minor issues, optional improvements
  - **Medium (0.3-0.7)**: Notable issues, should address
  - **High (0.7-1.0)**: Critical issues, must address

  ## Examples

      iex> CritiqueResult.new(%{
      ...>   issues: ["Calculation error"],
      ...>   suggestions: ["Re-check the math"],
      ...>   severity: 0.8
      ...> })
      {:ok, %CritiqueResult{severity: 0.8, issues: ["Calculation error"]}}

      iex> result = CritiqueResult.new!(%{severity: 0.5, issues: []})
      iex> CritiqueResult.severity_level(result)
      :medium

  """

  @type t :: %__MODULE__{
          issues: [String.t() | map()],
          suggestions: [String.t()],
          severity: float(),
          feedback: String.t() | nil,
          actionable: boolean(),
          metadata: map()
        }

  @type severity_level :: :low | :medium | :high

  @enforce_keys [:severity, :issues]
  defstruct [
    :issues,
    :suggestions,
    :severity,
    :feedback,
    :actionable,
    :metadata
  ]

  @doc """
  Default field values for CritiqueResult.
  """
  def defaults do
    %{
      issues: [],
      suggestions: [],
      severity: 0.0,
      feedback: nil,
      actionable: false,
      metadata: %{}
    }
  end

  @doc """
  Creates a new CritiqueResult from the given attributes.

  ## Options

  - `:issues` - List of identified issues (default: [])
  - `:suggestions` - List of improvement suggestions (default: [])
  - `:severity` - Overall severity score 0.0-1.0 (required)
  - `:feedback` - Natural language feedback (default: nil)
  - `:actionable` - Whether issues are actionable (default: false)
  - `:metadata` - Additional metadata (default: %{})

  ## Returns

  - `{:ok, CritiqueResult.t()}` on success
  - `{:error, reason}` on validation failure

  ## Examples

      iex> CritiqueResult.new(%{severity: 0.5, issues: ["error"]})
      {:ok, %CritiqueResult{severity: 0.5, issues: ["error"]}}

      iex> CritiqueResult.new(%{severity: :invalid})
      {:error, :invalid_severity}

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs_list = if is_map(attrs), do: Map.to_list(attrs), else: attrs
    attrs_map = Enum.into(attrs_list, %{})

    # Check if severity is explicitly provided
    case Map.has_key?(attrs_map, :severity) do
      false ->
        {:error, :invalid_severity}

      true ->
        merged = Map.merge(defaults(), attrs_map)

        with :ok <- validate_severity(merged.severity),
             :ok <- validate_issues(merged.issues) do
          result = struct(__MODULE__, merged)
          {:ok, %{result | actionable: compute_actionable(result)}}
        end
    end
  end

  @doc """
  Creates a new CritiqueResult, raising on error.

  Accepts either a keyword list or a map.

  """
  @spec new!(keyword() | map()) :: t()
  def new!(attrs) when is_list(attrs) or is_map(attrs) do
    case new(attrs) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "Invalid CritiqueResult: #{inspect(reason)}"
    end
  end

  @doc """
  Checks if the critique result has any issues.

  ## Examples

      iex> result = CritiqueResult.new!(%{severity: 0.5, issues: ["error"]})
      iex> CritiqueResult.has_issues?(result)
      true

      iex> result = CritiqueResult.new!(%{severity: 0.0, issues: []})
      iex> CritiqueResult.has_issues?(result)
      false

  """
  @spec has_issues?(t()) :: boolean()
  def has_issues?(%__MODULE__{issues: issues}) do
    is_list(issues) and length(issues) > 0
  end

  @doc """
  Checks if the candidate should be refined based on severity.

  Returns true if severity is above the threshold (default: 0.3).

  ## Options

  - `:threshold` - Severity threshold (default: 0.3)

  ## Examples

      iex> result = CritiqueResult.new!(%{severity: 0.7, issues: []})
      iex> CritiqueResult.should_refine?(result)
      true

      iex> result = CritiqueResult.new!(%{severity: 0.2, issues: []})
      iex> CritiqueResult.should_refine?(result)
      false

  """
  @spec should_refine?(t(), keyword()) :: boolean()
  def should_refine?(%__MODULE__{} = result, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.3)
    result.severity > threshold
  end

  @doc """
  Adds an issue to the critique result.

  ## Examples

      iex> result = CritiqueResult.new!(%{severity: 0.5, issues: []})
      iex> updated = CritiqueResult.add_issue(result, "New issue")
      iex> updated.issues
      ["New issue"]

  """
  @spec add_issue(t(), String.t() | map()) :: t()
  def add_issue(%__MODULE__{issues: issues} = result, issue) do
    %{result | issues: issues ++ [issue]}
  end

  @doc """
  Returns the severity level as an atom.

  - `:low` - severity 0.0 to 0.3
  - `:medium` - severity 0.3 to 0.7
  - `:high` - severity 0.7 to 1.0

  ## Examples

      iex> result = CritiqueResult.new!(%{severity: 0.2, issues: []})
      iex> CritiqueResult.severity_level(result)
      :low

      iex> result = CritiqueResult.new!(%{severity: 0.5, issues: []})
      iex> CritiqueResult.severity_level(result)
      :medium

      iex> result = CritiqueResult.new!(%{severity: 0.8, issues: []})
      iex> CritiqueResult.severity_level(result)
      :high

  """
  @spec severity_level(t()) :: severity_level()
  def severity_level(%__MODULE__{severity: severity}) when is_number(severity) do
    cond do
      severity < 0.3 -> :low
      severity < 0.7 -> :medium
      true -> :high
    end
  end

  @doc """
  Merges two critique results.

  Issues and suggestions are combined. The maximum severity is used.

  ## Examples

      iex> r1 = CritiqueResult.new!(%{severity: 0.5, issues: ["a"]})
      iex> r2 = CritiqueResult.new!(%{severity: 0.7, issues: ["b"]})
      iex> merged = CritiqueResult.merge(r1, r2)
      iex> {merged.severity, merged.issues}
      {0.7, ["a", "b"]}

  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = result1, %__MODULE__{} = result2) do
    %__MODULE__{
      issues: result1.issues ++ result2.issues,
      suggestions: result1.suggestions ++ result2.suggestions,
      severity: max(result1.severity, result2.severity),
      feedback: merge_feedback(result1.feedback, result2.feedback),
      actionable: result1.actionable or result2.actionable,
      metadata: Map.merge(result1.metadata, result2.metadata)
    }
  end

  @doc """
  Creates a critique result indicating no issues found.

  ## Examples

      iex> result = CritiqueResult.no_issues()
      iex> result.severity
      0.0

  """
  @spec no_issues() :: t()
  def no_issues do
    new!(%{
      severity: 0.0,
      issues: [],
      suggestions: [],
      feedback: "No issues found",
      actionable: false
    })
  end

  @doc """
  Creates a critique result from a verification result.

  Converts a VerificationResult to a CritiqueResult.

  ## Examples

      iex> vr = %Jido.AI.Accuracy.VerificationResult{
      ...>   score: 0.6,
      ...>   reasoning: "Some issues found"
      ...> }
      iex> cr = CritiqueResult.from_verification_result(vr)
      iex> cr.severity
      0.4

  """
  @spec from_verification_result(Jido.AI.Accuracy.VerificationResult.t()) :: t()
  def from_verification_result(%Jido.AI.Accuracy.VerificationResult{} = vr) do
    # Convert score to severity (lower score = higher severity)
    severity = 1.0 - (vr.score || 0.5)

    issues =
      if severity > 0.3 do
        ["Verification score: #{vr.score || 0.5}"]
      else
        []
      end

    new!(%{
      severity: severity,
      issues: issues,
      feedback: vr.reasoning,
      actionable: severity > 0.3,
      metadata: %{verification_result: true}
    })
  end

  # Private functions

  defp validate_severity(severity) when is_number(severity) and severity >= 0.0 and severity <= 1.0,
    do: :ok

  defp validate_severity(_), do: {:error, :invalid_severity}

  defp validate_issues(issues) when is_list(issues), do: :ok
  defp validate_issues(_), do: {:error, :invalid_issues}

  defp compute_actionable(%__MODULE__{issues: issues, severity: severity}) do
    has_issues = length(issues) > 0
    high_severity = severity > 0.3
    has_issues or high_severity
  end

  defp merge_feedback(nil, feedback2), do: feedback2
  defp merge_feedback(feedback1, nil), do: feedback1

  defp merge_feedback(feedback1, feedback2) when is_binary(feedback1) and is_binary(feedback2) do
    feedback1 <> "\n" <> feedback2
  end
end
