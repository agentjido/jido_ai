defmodule Jido.AI.Runner.ChainOfThought.ReasoningParser do
  @moduledoc """
  Parses and structures reasoning output from LLM responses.

  This module takes the text output from reasoning generation and extracts
  structured information including goals, steps, expected outcomes, and potential issues.
  """

  use TypedStruct

  typedstruct module: ReasoningPlan do
    @moduledoc """
    Structured representation of a reasoning plan.

    This struct contains all the information extracted from an LLM's reasoning output,
    organized for easy consumption by the execution engine.
    """

    field(:goal, String.t())
    field(:analysis, String.t())
    field(:steps, list(ReasoningStep.t()), default: [])
    field(:expected_results, String.t())
    field(:potential_issues, list(String.t()), default: [])
    field(:raw_text, String.t())
  end

  typedstruct module: ReasoningStep do
    @moduledoc """
    Represents a single step in a reasoning plan.

    Each step includes the action to take and the expected outcome,
    allowing for validation during execution.
    """

    field(:number, integer())
    field(:description, String.t())
    field(:expected_outcome, String.t())
  end

  @doc """
  Parses reasoning output text into a structured ReasoningPlan.

  Extracts sections like GOAL, ANALYSIS, EXECUTION_PLAN, EXPECTED_RESULTS,
  and POTENTIAL_ISSUES from the formatted reasoning output.

  ## Parameters

  - `text` - The reasoning output text from the LLM

  ## Returns

  - `{:ok, %ReasoningPlan{}}` on successful parsing
  - `{:error, reason}` if parsing fails

  ## Example

      iex> text = \"\"\"
      ...> GOAL: Process user data
      ...>
      ...> EXECUTION_PLAN:
      ...> Step 1: Validate input
      ...> Step 2: Transform data
      ...> \"\"\"
      iex> {:ok, plan} = ReasoningParser.parse(text)
      iex> plan.goal
      "Process user data"
      iex> length(plan.steps)
      2
  """
  @spec parse(String.t()) :: {:ok, ReasoningPlan.t()} | {:error, term()}
  def parse(text) when is_binary(text) do
    plan = %ReasoningPlan{
      goal: extract_section(text, "GOAL"),
      analysis: extract_section(text, "ANALYSIS"),
      steps: extract_steps(text),
      expected_results: extract_section(text, "EXPECTED_RESULTS"),
      potential_issues: extract_issues(text),
      raw_text: text
    }

    {:ok, plan}
  rescue
    error ->
      {:error, "Failed to parse reasoning: #{inspect(error)}"}
  end

  def parse(_), do: {:error, "Invalid reasoning text: must be a string"}

  @doc """
  Extracts a simple text section from the reasoning output.

  Looks for a section header (e.g., "GOAL:") and extracts the text
  until the next section or end of text.

  ## Parameters

  - `text` - The full reasoning text
  - `section_name` - The section to extract (e.g., "GOAL", "ANALYSIS")

  ## Returns

  The extracted section text, or an empty string if not found.
  """
  @spec extract_section(String.t(), String.t()) :: String.t()
  def extract_section(text, section_name) do
    # Match section header followed by content until next section or end
    pattern = ~r/#{section_name}:\s*\n?(.*?)(?=\n[A-Z_]+:|\z)/s

    case Regex.run(pattern, text, capture: :all_but_first) do
      [content] -> String.trim(content)
      _ -> ""
    end
  end

  @doc """
  Extracts execution steps from the EXECUTION_PLAN section.

  Parses numbered steps (Step 1:, Step 2:, etc.) and creates ReasoningStep structs.

  ## Parameters

  - `text` - The full reasoning text containing an EXECUTION_PLAN section

  ## Returns

  A list of `%ReasoningStep{}` structs.
  """
  @spec extract_steps(String.t()) :: list(ReasoningStep.t())
  def extract_steps(text) do
    execution_plan = extract_section(text, "EXECUTION_PLAN")

    if execution_plan == "" do
      []
    else
      # Match "Step N: description [expected outcome]"
      ~r/Step\s+(\d+):\s*(.+?)(?=Step\s+\d+:|$)/s
      |> Regex.scan(execution_plan)
      |> Enum.map(fn [_match, num_str, content] ->
        {number, _} = Integer.parse(num_str)
        {description, expected_outcome} = split_step_content(content)

        %ReasoningStep{
          number: number,
          description: String.trim(description),
          expected_outcome: String.trim(expected_outcome)
        }
      end)
    end
  end

  @doc """
  Extracts potential issues from the POTENTIAL_ISSUES section.

  ## Parameters

  - `text` - The full reasoning text containing a POTENTIAL_ISSUES section

  ## Returns

  A list of issue strings.
  """
  @spec extract_issues(String.t()) :: list(String.t())
  def extract_issues(text) do
    issues_text = extract_section(text, "POTENTIAL_ISSUES")

    if issues_text == "" do
      []
    else
      # Split on bullet points, dashes, or newlines
      issues_text
      |> String.split(~r/[-•*]\s*|\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
    end
  end

  # Private helper functions

  defp split_step_content(content) do
    content = String.trim(content)

    # Look for patterns like "description [expected: outcome]" or "description (outcome)"
    case Regex.run(~r/^(.*?)[\[\(](?:expected:?\s*)?(.*?)[\]\)]$/s, content) do
      [_match, desc, outcome] ->
        {desc, outcome}

      _ ->
        # No expected outcome found, treat entire content as description
        {content, ""}
    end
  end

  @doc """
  Validates that a reasoning plan has all required components.

  ## Parameters

  - `plan` - A %ReasoningPlan{} struct

  ## Returns

  - `:ok` if valid
  - `{:error, reason}` if invalid
  """
  @spec validate(ReasoningPlan.t()) :: :ok | {:error, String.t()}
  def validate(%ReasoningPlan{goal: goal}) when goal == "" or is_nil(goal) do
    {:error, "Reasoning plan missing goal"}
  end

  def validate(%ReasoningPlan{steps: []}) do
    {:error, "Reasoning plan has no execution steps"}
  end

  def validate(%ReasoningPlan{steps: steps}) do
    if Enum.all?(steps, &valid_step?/1) do
      :ok
    else
      {:error, "Reasoning plan contains invalid steps"}
    end
  end

  defp valid_step?(%ReasoningStep{description: desc}) when desc != "" and not is_nil(desc),
    do: true

  defp valid_step?(_), do: false
end
