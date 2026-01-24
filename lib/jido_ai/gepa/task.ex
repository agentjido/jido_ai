defmodule Jido.AI.GEPA.Task do
  @moduledoc """
  Represents a task in the GEPA evaluation process.

  A Task defines an input prompt and success criteria for evaluating
  prompt variants. Tasks are collected into task sets for batch evaluation.

  ## Fields

  - `id` - Unique identifier for this task
  - `input` - The task input/prompt to send to the LLM
  - `expected` - Expected output (string for exact match, or validation function)
  - `validator` - Optional custom validation function `(output) -> boolean`
  - `metadata` - Additional data (category, difficulty, tags, etc.)

  ## Usage

      # Create a task with expected output
      task = Task.new!(%{
        input: "What is 2 + 2?",
        expected: "4"
      })

      # Create a task with custom validator
      task = Task.new!(%{
        input: "Write a function to add two numbers",
        validator: fn output -> String.contains?(output, "def add") end
      })

      # Check if output passes
      Task.success?(task, "The answer is 4")
      #=> true
  """

  @type validator :: (String.t() -> boolean())

  @type t :: %__MODULE__{
          id: String.t(),
          input: String.t(),
          expected: String.t() | nil,
          validator: validator() | nil,
          metadata: map()
        }

  @enforce_keys [:id, :input]
  defstruct [
    :id,
    :input,
    :expected,
    :validator,
    metadata: %{}
  ]

  @doc """
  Creates a new Task from the given attributes.

  ## Parameters

  - `attrs` - Map with task attributes:
    - `:input` (required) - The task input/prompt
    - `:id` (optional) - Unique ID, auto-generated if not provided
    - `:expected` (optional) - Expected output string
    - `:validator` (optional) - Custom validation function
    - `:metadata` (optional) - Additional data

  At least one of `:expected` or `:validator` should be provided for meaningful evaluation.

  ## Returns

  `{:ok, task}` on success, `{:error, reason}` on failure.

  ## Examples

      iex> Task.new(%{input: "What is 2+2?", expected: "4"})
      {:ok, %Task{input: "What is 2+2?", expected: "4", ...}}

      iex> Task.new(%{})
      {:error, :input_required}
  """
  @spec new(map()) :: {:ok, t()} | {:error, atom()}
  def new(attrs) when is_map(attrs) do
    case validate_attrs(attrs) do
      :ok ->
        task = build_task(attrs)
        {:ok, task}

      {:error, _} = error ->
        error
    end
  end

  def new(_), do: {:error, :invalid_attrs}

  @doc """
  Creates a new Task, raising on error.

  Same as `new/1` but raises `ArgumentError` on invalid input.
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, task} -> task
      {:error, reason} -> raise ArgumentError, error_message(reason)
    end
  end

  @doc """
  Checks if the given output passes this task's success criteria.

  Uses the validator function if provided, otherwise performs a
  flexible match against the expected output.

  ## Parameters

  - `task` - The task to check against
  - `output` - The output string to validate

  ## Returns

  `true` if the output passes, `false` otherwise.

  ## Security Note

  When using a custom `:validator` function, ensure it comes from trusted code only.
  Validator functions are executed during `success?/2` calls and have access to the
  output string. Do NOT construct Task structs with validators from untrusted sources
  (e.g., user input, external APIs, or deserialized data from untrusted origins).

  ## Examples

      iex> task = Task.new!(%{input: "2+2?", expected: "4"})
      iex> Task.success?(task, "The answer is 4")
      true

      iex> task = Task.new!(%{input: "2+2?", validator: &String.contains?(&1, "4")})
      iex> Task.success?(task, "I think it's 4")
      true
  """
  @spec success?(t(), String.t()) :: boolean()
  def success?(%__MODULE__{validator: validator}, output) when is_function(validator, 1) do
    validator.(output) == true
  rescue
    _ -> false
  end

  def success?(%__MODULE__{expected: expected}, output) when is_binary(expected) do
    flexible_match?(expected, output)
  end

  def success?(%__MODULE__{expected: nil, validator: nil}, _output) do
    # No success criteria defined - always passes (useful for exploratory tasks)
    true
  end

  @doc """
  Creates a simple task from just an input string.

  Useful for quick task creation when success criteria will be
  determined later or externally.

  ## Examples

      iex> task = Task.from_input("Explain recursion")
      %Task{input: "Explain recursion", expected: nil, ...}
  """
  @spec from_input(String.t()) :: t()
  def from_input(input) when is_binary(input) do
    new!(%{input: input})
  end

  @doc """
  Creates multiple tasks from a list of input-expected pairs.

  ## Examples

      iex> tasks = Task.from_pairs([
      ...>   {"What is 2+2?", "4"},
      ...>   {"What is 3+3?", "6"}
      ...> ])
      [%Task{input: "What is 2+2?", expected: "4"}, ...]
  """
  @spec from_pairs([{String.t(), String.t()}]) :: [t()]
  def from_pairs(pairs) when is_list(pairs) do
    Enum.map(pairs, fn {input, expected} ->
      new!(%{input: input, expected: expected})
    end)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp validate_attrs(attrs) do
    cond do
      not Map.has_key?(attrs, :input) -> {:error, :input_required}
      not is_binary(attrs.input) -> {:error, :invalid_input}
      String.trim(attrs.input) == "" -> {:error, :empty_input}
      true -> :ok
    end
  end

  defp build_task(attrs) do
    %__MODULE__{
      id: Map.get(attrs, :id, generate_id()),
      input: attrs.input,
      expected: Map.get(attrs, :expected),
      validator: Map.get(attrs, :validator),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  defp generate_id do
    "task_#{Jido.Util.generate_id()}"
  end

  # Flexible matching - checks if expected is contained in output or if normalized versions match
  defp flexible_match?(expected, output) when is_binary(expected) and is_binary(output) do
    expected_normalized = normalize(expected)
    output_normalized = normalize(output)

    String.contains?(output_normalized, expected_normalized) or
      output_normalized == expected_normalized
  end

  defp flexible_match?(_, _), do: false

  defp normalize(str) do
    str
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp error_message(:input_required), do: "input is required"
  defp error_message(:invalid_input), do: "input must be a string"
  defp error_message(:empty_input), do: "input cannot be empty"
  defp error_message(:invalid_attrs), do: "attrs must be a map"
end
