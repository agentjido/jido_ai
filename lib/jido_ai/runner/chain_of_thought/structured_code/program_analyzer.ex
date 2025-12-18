defmodule Jido.AI.Runner.ChainOfThought.StructuredCode.ProgramAnalyzer do
  @moduledoc """
  Analyzes code requirements to identify program structures needed.

  Provides:
  - Structural pattern extraction from specifications
  - Control flow identification (conditional, iterative, recursive)
  - Data flow analysis identifying transformations and dependencies
  - Complexity estimation guiding structure selection

  ## Usage

      requirements = "Create a function that filters a list and transforms each element"

      {:ok, analysis} = ProgramAnalyzer.analyze(requirements)
      # => %{
      #   structures: [:sequence, :branch, :loop],
      #   control_flow: %{type: :iterative, pattern: :filter_map},
      #   data_flow: %{input: :list, transformations: [:filter, :map], output: :list},
      #   complexity: :moderate
      # }
  """

  require Logger

  @type structure :: :sequence | :branch | :loop | :recursion | :pipeline | :composition
  @type control_flow_type :: :sequential | :conditional | :iterative | :recursive
  @type complexity :: :trivial | :simple | :moderate | :complex | :very_complex

  @type analysis :: %{
          structures: list(structure()),
          control_flow: %{
            type: control_flow_type(),
            pattern: atom(),
            required_features: list(atom())
          },
          data_flow: %{
            input: atom(),
            transformations: list(atom()),
            output: atom(),
            dependencies: list(atom())
          },
          complexity: complexity(),
          elixir_patterns: list(atom())
        }

  @doc """
  Analyzes code requirements and identifies structural patterns.

  ## Parameters

  - `requirements` - Text description of code requirements
  - `opts` - Options:
    - `:language` - Target language (default: :elixir)
    - `:context` - Additional context for analysis

  ## Returns

  - `{:ok, analysis}` - Analysis results
  - `{:error, reason}` - Analysis failed

  ## Examples

      {:ok, analysis} = ProgramAnalyzer.analyze("Sort a list of numbers")
      # => analysis.structures will include [:sequence, :loop]
  """
  @spec analyze(String.t(), keyword()) :: {:ok, analysis()} | {:error, term()}
  def analyze(requirements, opts \\ []) do
    language = Keyword.get(opts, :language, :elixir)
    context = Keyword.get(opts, :context, %{})

    with {:ok, tokens} <- tokenize_requirements(requirements),
         {:ok, structures} <- identify_structures(tokens, language),
         {:ok, control_flow} <- analyze_control_flow(tokens, structures),
         {:ok, data_flow} <- analyze_data_flow(tokens),
         {:ok, complexity} <- estimate_complexity(structures, control_flow, data_flow) do
      elixir_patterns = select_elixir_patterns(structures, control_flow, data_flow)

      analysis = %{
        structures: structures,
        control_flow: control_flow,
        data_flow: data_flow,
        complexity: complexity,
        elixir_patterns: elixir_patterns,
        context: context
      }

      {:ok, analysis}
    end
  end

  @doc """
  Identifies control flow patterns in requirements.

  ## Parameters

  - `requirements` - Text description
  - `structures` - Previously identified structures

  ## Returns

  Control flow information map
  """
  @spec identify_control_flow(String.t(), list(structure())) ::
          {:ok, control_flow_type()} | {:error, term()}
  def identify_control_flow(requirements, structures \\ []) do
    with {:ok, tokens} <- tokenize_requirements(requirements),
         {:ok, flow} <- analyze_control_flow(tokens, structures) do
      {:ok, flow.type}
    end
  end

  @doc """
  Analyzes data transformations in requirements.

  ## Parameters

  - `requirements` - Text description

  ## Returns

  Data flow information map
  """
  @spec analyze_data_transformations(String.t()) :: {:ok, list(atom())} | {:error, term()}
  def analyze_data_transformations(requirements) do
    with {:ok, tokens} <- tokenize_requirements(requirements),
         {:ok, data_flow} <- analyze_data_flow(tokens) do
      {:ok, data_flow.transformations}
    end
  end

  @doc """
  Estimates complexity of implementation.

  ## Parameters

  - `requirements` - Text description

  ## Returns

  Complexity level
  """
  @spec estimate_implementation_complexity(String.t()) :: {:ok, complexity()} | {:error, term()}
  def estimate_implementation_complexity(requirements) do
    with {:ok, analysis} <- analyze(requirements) do
      {:ok, analysis.complexity}
    end
  end

  # Private functions

  defp tokenize_requirements(requirements) do
    # Tokenize requirements into keywords and phrases
    tokens =
      requirements
      |> String.downcase()
      |> String.split(~r/[,\.\s]+/, trim: true)
      |> Enum.reject(&(&1 == ""))

    {:ok, tokens}
  end

  defp identify_structures(tokens, language) do
    structures = []

    # Sequence indicators
    structures =
      if has_sequence_indicators?(tokens) do
        [:sequence | structures]
      else
        structures
      end

    # Branch indicators
    structures =
      if has_branch_indicators?(tokens) do
        [:branch | structures]
      else
        structures
      end

    # Loop indicators
    structures =
      if has_loop_indicators?(tokens) do
        [:loop | structures]
      else
        structures
      end

    # Recursion indicators
    structures =
      if has_recursion_indicators?(tokens) do
        [:recursion | structures]
      else
        structures
      end

    # Pipeline indicators (Elixir-specific)
    structures =
      if language == :elixir and has_pipeline_indicators?(tokens) do
        [:pipeline | structures]
      else
        structures
      end

    # Composition indicators
    structures =
      if has_composition_indicators?(tokens) do
        [:composition | structures]
      else
        structures
      end

    # Default to sequence if nothing else identified
    structures =
      if Enum.empty?(structures) do
        [:sequence]
      else
        Enum.uniq(structures)
      end

    {:ok, structures}
  end

  defp has_sequence_indicators?(tokens) do
    sequence_keywords = [
      "first",
      "then",
      "after",
      "next",
      "finally",
      "step",
      "transform",
      "process"
    ]

    Enum.any?(tokens, &(&1 in sequence_keywords))
  end

  defp has_branch_indicators?(tokens) do
    branch_keywords = [
      "if",
      "when",
      "case",
      "match",
      "condition",
      "conditional",
      "choose",
      "select",
      "depends",
      "different",
      "otherwise",
      "else"
    ]

    Enum.any?(tokens, &(&1 in branch_keywords))
  end

  defp has_loop_indicators?(tokens) do
    loop_keywords = [
      "each",
      "every",
      "all",
      "iterate",
      "loop",
      "repeat",
      "multiple",
      "collection",
      "list",
      "map",
      "filter",
      "reduce",
      "fold"
    ]

    Enum.any?(tokens, &(&1 in loop_keywords))
  end

  defp has_recursion_indicators?(tokens) do
    recursion_keywords = [
      "recursive",
      "recursion",
      "tree",
      "nested",
      "deep",
      "hierarchy",
      "traverse",
      "walk"
    ]

    Enum.any?(tokens, &(&1 in recursion_keywords))
  end

  defp has_pipeline_indicators?(tokens) do
    pipeline_keywords = [
      "pipeline",
      "chain",
      "sequence",
      "flow",
      "transform",
      "process",
      "convert"
    ]

    Enum.any?(tokens, &(&1 in pipeline_keywords))
  end

  defp has_composition_indicators?(tokens) do
    composition_keywords = [
      "compose",
      "combine",
      "merge",
      "integrate",
      "assemble",
      "build"
    ]

    Enum.any?(tokens, &(&1 in composition_keywords))
  end

  defp analyze_control_flow(tokens, structures) do
    # Determine control flow type based on structures
    type =
      cond do
        :recursion in structures -> :recursive
        :loop in structures -> :iterative
        :branch in structures -> :conditional
        true -> :sequential
      end

    # Identify specific pattern
    pattern = identify_pattern(tokens, type)

    # Required language features
    required_features = derive_required_features(type, structures)

    {:ok,
     %{
       type: type,
       pattern: pattern,
       required_features: required_features
     }}
  end

  defp identify_pattern(tokens, type) do
    cond do
      type == :iterative ->
        cond do
          Enum.any?(tokens, &(&1 in ["map", "transform"])) -> :map
          Enum.any?(tokens, &(&1 in ["filter", "select"])) -> :filter
          Enum.any?(tokens, &(&1 in ["reduce", "fold", "accumulate"])) -> :reduce
          Enum.any?(tokens, &(&1 in ["flat_map", "flatten"])) -> :flat_map
          true -> :enum_each
        end

      type == :conditional ->
        cond do
          Enum.any?(tokens, &(&1 in ["match", "pattern"])) -> :pattern_match
          Enum.any?(tokens, &(&1 in ["case", "switch"])) -> :case
          Enum.any?(tokens, &(&1 in ["guard", "constraint"])) -> :guard
          true -> :if_else
        end

      type == :recursive ->
        cond do
          Enum.any?(tokens, &(&1 in ["tree", "binary"])) -> :tree_recursion
          Enum.any?(tokens, &(&1 in ["tail", "accumulator"])) -> :tail_recursion
          true -> :simple_recursion
        end

      true ->
        :sequential
    end
  end

  defp derive_required_features(type, structures) do
    features = []

    features =
      if type in [:iterative, :recursive] do
        [:enum | features]
      else
        features
      end

    features =
      if :branch in structures or type == :conditional do
        [:pattern_matching | features]
      else
        features
      end

    features =
      if :pipeline in structures do
        [:pipe_operator | features]
      else
        features
      end

    features =
      if :composition in structures do
        [:higher_order_functions | features]
      else
        features
      end

    Enum.uniq(features)
  end

  defp analyze_data_flow(tokens) do
    # Identify input type
    input_type = identify_input_type(tokens)

    # Identify transformations
    transformations = identify_transformations(tokens)

    # Identify output type
    output_type = identify_output_type(tokens, input_type)

    # Identify dependencies
    dependencies = identify_dependencies(tokens)

    {:ok,
     %{
       input: input_type,
       transformations: transformations,
       output: output_type,
       dependencies: dependencies
     }}
  end

  defp identify_input_type(tokens) do
    cond do
      Enum.any?(tokens, &(&1 in ["list", "collection", "array"])) -> :list
      Enum.any?(tokens, &(&1 in ["map", "dictionary", "hash"])) -> :map
      Enum.any?(tokens, &(&1 in ["string", "text"])) -> :string
      Enum.any?(tokens, &(&1 in ["number", "integer", "float"])) -> :number
      Enum.any?(tokens, &(&1 in ["struct", "record"])) -> :struct
      true -> :any
    end
  end

  defp identify_transformations(tokens) do
    transformations = []

    transformations =
      if Enum.any?(tokens, &(&1 in ["map", "transform", "convert"])) do
        [:map | transformations]
      else
        transformations
      end

    transformations =
      if Enum.any?(tokens, &(&1 in ["filter", "select", "choose"])) do
        [:filter | transformations]
      else
        transformations
      end

    transformations =
      if Enum.any?(tokens, &(&1 in ["reduce", "fold", "accumulate", "aggregate"])) do
        [:reduce | transformations]
      else
        transformations
      end

    transformations =
      if Enum.any?(tokens, &(&1 in ["sort", "order"])) do
        [:sort | transformations]
      else
        transformations
      end

    transformations =
      if Enum.any?(tokens, &(&1 in ["group", "partition"])) do
        [:group | transformations]
      else
        transformations
      end

    transformations =
      if Enum.any?(tokens, &(&1 in ["validate", "check"])) do
        [:validate | transformations]
      else
        transformations
      end

    transformations
  end

  defp identify_output_type(tokens, input_type) do
    # Output type often matches input type unless explicitly transformed
    cond do
      Enum.any?(tokens, &(&1 in ["count", "size", "length"])) -> :number
      Enum.any?(tokens, &(&1 in ["boolean", "true", "false", "check"])) -> :boolean
      Enum.any?(tokens, &(&1 in ["string", "text", "format"])) -> :string
      true -> input_type
    end
  end

  defp identify_dependencies(tokens) do
    dependencies = []

    dependencies =
      if Enum.any?(tokens, &(&1 in ["async", "parallel", "concurrent"])) do
        [:task | dependencies]
      else
        dependencies
      end

    dependencies =
      if Enum.any?(tokens, &(&1 in ["cache", "memoize"])) do
        [:cache | dependencies]
      else
        dependencies
      end

    dependencies =
      if Enum.any?(tokens, &(&1 in ["validate", "schema"])) do
        [:validation | dependencies]
      else
        dependencies
      end

    dependencies
  end

  defp estimate_complexity(structures, control_flow, data_flow) do
    score = 0

    # Structure complexity
    score = score + length(structures) * 2

    # Control flow complexity
    score =
      case control_flow.type do
        :sequential -> score + 1
        :conditional -> score + 3
        :iterative -> score + 4
        :recursive -> score + 6
      end

    # Data flow complexity
    score = score + length(data_flow.transformations) * 2
    score = score + length(data_flow.dependencies) * 3

    # Map to complexity level
    complexity =
      cond do
        score <= 5 -> :trivial
        score <= 10 -> :simple
        score <= 20 -> :moderate
        score <= 35 -> :complex
        true -> :very_complex
      end

    {:ok, complexity}
  end

  defp select_elixir_patterns(structures, control_flow, data_flow) do
    patterns = []

    # Pipeline pattern
    patterns =
      if :pipeline in structures or length(data_flow.transformations) > 2 do
        [:pipeline | patterns]
      else
        patterns
      end

    # Pattern matching
    patterns =
      if :branch in structures or control_flow.type == :conditional do
        [:pattern_matching | patterns]
      else
        patterns
      end

    # With syntax (for error handling)
    patterns =
      if length(data_flow.transformations) > 1 or length(data_flow.dependencies) > 0 do
        [:with_syntax | patterns]
      else
        patterns
      end

    # Higher-order functions
    patterns =
      if control_flow.type == :iterative or :composition in structures do
        [:higher_order_functions | patterns]
      else
        patterns
      end

    # Recursion
    patterns =
      if control_flow.type == :recursive do
        [:recursion | patterns]
      else
        patterns
      end

    # Guards
    patterns =
      if control_flow.pattern in [:guard, :pattern_match] do
        [:guards | patterns]
      else
        patterns
      end

    Enum.uniq(patterns)
  end
end
