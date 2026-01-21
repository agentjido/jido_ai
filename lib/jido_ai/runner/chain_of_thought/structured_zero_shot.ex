defmodule Jido.AI.Runner.ChainOfThought.StructuredZeroShot do
  @moduledoc """
  Structured zero-shot Chain-of-Thought reasoning for code generation.

  This module implements structured zero-shot CoT optimized for code generation
  tasks using the UNDERSTAND-PLAN-IMPLEMENT-VALIDATE framework. Research shows
  13.79% improvement over standard CoT when reasoning structure matches program
  structure.

  ## Structure

  The structured approach uses four key sections:

  1. **UNDERSTAND**: Analyze requirements and constraints
  2. **PLAN**: Design solution structure and approach
  3. **IMPLEMENT**: Map plan to code with Elixir idioms
  4. **VALIDATE**: Identify edge cases and validation strategy

  ## Elixir-Specific Guidance

  Provides guidance for Elixir best practices:
  - Pipeline transformations (`|>`)
  - Pattern matching (function heads, case, with)
  - Error handling (with-syntax, tagged tuples)
  - Functional patterns (map, reduce, recursion)

  ## Usage

      # Generate structured reasoning for code
      {:ok, reasoning} = StructuredZeroShot.generate(
        problem: "Create a function to calculate Fibonacci numbers",
        language: :elixir,
        temperature: 0.2
      )

      # Access structured sections
      reasoning.sections
      # => %{
      #   understand: %{requirements: [...], constraints: [...]},
      #   plan: %{approach: "...", structure: [...]},
      #   implement: %{steps: [...], patterns: [...]},
      #   validate: %{edge_cases: [...], tests: [...]}
      # }

  ## Temperature Guidelines

  - 0.2-0.3: Consistent, focused code generation (recommended)
  - 0.3-0.4: Slight creativity for alternative approaches
  - Higher: More experimental solutions (use with caution)

  ## Supported Languages

  - `:elixir` - Full support with Elixir-specific guidance
  - `:general` - Language-agnostic structured reasoning
  """

  require Logger
  alias Jido.AI.Actions.TextCompletion
  alias Jido.AI.{Model, Prompt}

  @default_temperature 0.2
  @default_max_tokens 3000

  @doc """
  Generates structured zero-shot CoT reasoning for code generation.

  Uses the UNDERSTAND-PLAN-IMPLEMENT-VALIDATE framework to elicit
  structured reasoning from the LLM optimized for code generation.

  ## Parameters

  - `opts` - Keyword list with options:
    - `:problem` (required) - The code generation task description
    - `:language` - Target language (default: :elixir)
    - `:model` - Model string (default: "gpt-4o")
    - `:temperature` - Temperature for generation (default: 0.2)
    - `:max_tokens` - Maximum tokens in response (default: 3000)
    - `:context` - Additional context (default: %{})

  ## Returns

  - `{:ok, reasoning}` - Structured reasoning map
  - `{:error, reason}` - Generation failed

  ## Examples

      {:ok, reasoning} = StructuredZeroShot.generate(
        problem: "Write a function to merge two sorted lists",
        language: :elixir,
        temperature: 0.2
      )

      reasoning.sections.understand.requirements
      # => ["Merge two sorted lists", "Maintain sort order", ...]

      reasoning.sections.plan.approach
      # => "Use recursive pattern matching to merge elements..."
  """
  @spec generate(keyword()) :: {:ok, map()} | {:error, term()}
  def generate(opts) do
    with {:ok, problem} <- validate_problem(opts),
         {:ok, language} <- validate_language(opts),
         {:ok, prompt} <- build_structured_prompt(problem, language, opts),
         {:ok, model} <- build_model(opts),
         {:ok, response} <- generate_reasoning(prompt, model, opts),
         {:ok, parsed} <- parse_structured_reasoning(response, problem, language) do
      {:ok, parsed}
    else
      {:error, reason} = error ->
        Logger.error("Structured zero-shot reasoning generation failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Builds a structured prompt with UNDERSTAND-PLAN-IMPLEMENT-VALIDATE framework.

  ## Parameters

  - `problem` - The code generation task
  - `language` - Target language (:elixir or :general)
  - `opts` - Additional options for prompt customization

  ## Returns

  - `{:ok, prompt}` - Jido.AI.Prompt struct
  - `{:error, reason}` - Prompt building failed
  """
  @spec build_structured_prompt(String.t(), atom(), keyword()) ::
          {:ok, Prompt.t()} | {:error, term()}
  def build_structured_prompt(problem, language, opts \\ []) do
    context = Keyword.get(opts, :context, %{})
    language_guidance = get_language_guidance(language)

    template = """
    #{format_context(context)}Task: #{problem}

    Let's solve this code generation task step by step using structured reasoning.

    #{language_guidance}

    Please organize your reasoning into these sections:

    ## UNDERSTAND
    - What are the core requirements?
    - What are the constraints and edge cases?
    - What data structures are involved?
    - What is the expected input/output?

    ## PLAN
    - What is the overall approach?
    - What are the key steps in the algorithm?
    - How should the code be structured?
    - What patterns or techniques should be used?

    ## IMPLEMENT
    - How do we translate the plan into code?
    - What specific language features should we use?
    - How do we handle edge cases?
    - What would the code structure look like?

    ## VALIDATE
    - What edge cases need testing?
    - What potential errors could occur?
    - How can we verify correctness?
    - What test cases would be valuable?

    Think through each section carefully.
    """

    prompt = Prompt.new(:user, String.trim(template))
    {:ok, prompt}
  end

  @doc """
  Parses structured LLM response into organized sections.

  Extracts UNDERSTAND, PLAN, IMPLEMENT, and VALIDATE sections
  from the response and structures them for downstream use.

  ## Parameters

  - `response_text` - Raw LLM response text
  - `problem` - Original problem statement
  - `language` - Target language

  ## Returns

  - `{:ok, reasoning}` - Structured reasoning map
  - `{:error, reason}` - Parsing failed
  """
  @spec parse_structured_reasoning(String.t(), String.t(), atom()) ::
          {:ok, map()} | {:error, term()}
  def parse_structured_reasoning(response_text, problem, language) do
    sections = extract_sections(response_text)

    understand = parse_understand_section(sections[:understand] || "")
    plan = parse_plan_section(sections[:plan] || "")
    implement = parse_implement_section(sections[:implement] || "")
    validate = parse_validate_section(sections[:validate] || "")

    reasoning = %{
      problem: problem,
      language: language,
      reasoning_text: response_text,
      sections: %{
        understand: understand,
        plan: plan,
        implement: implement,
        validate: validate
      },
      timestamp: DateTime.utc_now()
    }

    {:ok, reasoning}
  end

  @doc """
  Extracts the four main sections from structured reasoning.

  Identifies UNDERSTAND, PLAN, IMPLEMENT, and VALIDATE sections
  in the response text.

  ## Parameters

  - `text` - LLM response text

  ## Returns

  Map with section names as keys and section text as values
  """
  @spec extract_sections(String.t()) :: map()
  def extract_sections(text) do
    # Extract each section using pattern matching
    understand_match = Regex.run(~r/##\s*UNDERSTAND\s*\n(.*?)(?=##\s*\w+|\z)/is, text)
    plan_match = Regex.run(~r/##\s*PLAN\s*\n(.*?)(?=##\s*\w+|\z)/is, text)
    implement_match = Regex.run(~r/##\s*IMPLEMENT\s*\n(.*?)(?=##\s*\w+|\z)/is, text)
    validate_match = Regex.run(~r/##\s*VALIDATE\s*\n(.*?)(?=##\s*\w+|\z)/is, text)

    %{
      understand: if(understand_match, do: String.trim(Enum.at(understand_match, 1)), else: nil),
      plan: if(plan_match, do: String.trim(Enum.at(plan_match, 1)), else: nil),
      implement: if(implement_match, do: String.trim(Enum.at(implement_match, 1)), else: nil),
      validate: if(validate_match, do: String.trim(Enum.at(validate_match, 1)), else: nil)
    }
  end

  @doc """
  Parses the UNDERSTAND section into structured components.

  Extracts requirements, constraints, data structures, and input/output
  specifications from the UNDERSTAND section.

  ## Parameters

  - `text` - UNDERSTAND section text

  ## Returns

  Map with structured understanding components
  """
  @spec parse_understand_section(String.t()) :: map()
  def parse_understand_section(text) do
    lines = String.split(text, "\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    %{
      requirements: extract_list_items(text, ~r/(?:requirements?|what.*needed)/i),
      constraints: extract_list_items(text, ~r/(?:constraints?|limitations?|edge cases?)/i),
      data_structures: extract_list_items(text, ~r/(?:data structures?|structures?)/i),
      input_output: extract_list_items(text, ~r/(?:input|output|expected)/i),
      all_points: filter_bullet_points(lines)
    }
  end

  @doc """
  Parses the PLAN section into structured components.

  Extracts approach, algorithm steps, structure, and patterns
  from the PLAN section.

  ## Parameters

  - `text` - PLAN section text

  ## Returns

  Map with structured planning components
  """
  @spec parse_plan_section(String.t()) :: map()
  def parse_plan_section(text) do
    lines = String.split(text, "\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    %{
      approach: extract_approach(text),
      algorithm_steps: extract_list_items(text, ~r/(?:steps?|algorithm)/i),
      structure: extract_list_items(text, ~r/(?:structure|organized?)/i),
      patterns: extract_list_items(text, ~r/(?:patterns?|techniques?)/i),
      all_points: filter_bullet_points(lines)
    }
  end

  @doc """
  Parses the IMPLEMENT section into structured components.

  Extracts implementation steps, language features, error handling,
  and code structure from the IMPLEMENT section.

  ## Parameters

  - `text` - IMPLEMENT section text

  ## Returns

  Map with structured implementation components
  """
  @spec parse_implement_section(String.t()) :: map()
  def parse_implement_section(text) do
    lines = String.split(text, "\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    %{
      steps: extract_list_items(text, ~r/(?:steps?|translate|implementation)/i),
      language_features: extract_list_items(text, ~r/(?:features?|language|syntax)/i),
      error_handling: extract_list_items(text, ~r/(?:error|exception|handle)/i),
      code_structure: extract_code_blocks(text),
      all_points: filter_bullet_points(lines)
    }
  end

  @doc """
  Parses the VALIDATE section into structured components.

  Extracts edge cases, error scenarios, verification methods,
  and test cases from the VALIDATE section.

  ## Parameters

  - `text` - VALIDATE section text

  ## Returns

  Map with structured validation components
  """
  @spec parse_validate_section(String.t()) :: map()
  def parse_validate_section(text) do
    lines = String.split(text, "\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    %{
      edge_cases: extract_list_items(text, ~r/(?:edge cases?)/i),
      error_scenarios: extract_list_items(text, ~r/(?:errors?|failures?)/i),
      verification: extract_list_items(text, ~r/(?:verif\w*|correctness|validation)/i),
      test_cases: extract_list_items(text, ~r/(?:test cases?|tests?)/i),
      all_points: filter_bullet_points(lines)
    }
  end

  # Private helper functions

  @spec validate_problem(keyword()) :: {:ok, String.t()} | {:error, term()}
  defp validate_problem(opts) do
    case Keyword.get(opts, :problem) do
      nil -> {:error, "Problem is required"}
      problem when is_binary(problem) and byte_size(problem) > 0 -> {:ok, problem}
      _ -> {:error, "Problem must be a non-empty string"}
    end
  end

  @spec validate_language(keyword()) :: {:ok, atom()} | {:error, term()}
  defp validate_language(opts) do
    language = Keyword.get(opts, :language, :elixir)

    if language in [:elixir, :general] do
      {:ok, language}
    else
      {:error, "Language must be :elixir or :general"}
    end
  end

  @spec get_language_guidance(atom()) :: String.t()
  defp get_language_guidance(:elixir) do
    """
    Target Language: Elixir

    Consider Elixir best practices:
    - Use pipeline operators (|>) for data transformations
    - Leverage pattern matching in function heads
    - Use with-syntax for error handling with multiple steps
    - Prefer Enum/Stream functions over manual recursion
    - Return {:ok, result} or {:error, reason} tuples
    - Use guards for input validation
    - Implement recursive solutions when appropriate
    - Consider tail-call optimization for recursion
    """
  end

  defp get_language_guidance(:general) do
    """
    Target Language: General-purpose

    Consider general programming principles:
    - Clear variable naming and code organization
    - Appropriate data structures for the task
    - Error handling and edge case management
    - Algorithmic efficiency and readability
    - Testing and validation strategy
    """
  end

  @spec format_context(map()) :: String.t()
  defp format_context(context) when context == %{}, do: ""

  defp format_context(context) do
    context
    |> Enum.map_join("\n", fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> then(&"Context:\n#{&1}\n\n")
  end

  @spec build_model(keyword()) :: {:ok, Model.t()} | {:error, term()}
  defp build_model(opts) do
    model_string = Keyword.get(opts, :model, "gpt-4o")
    temperature = Keyword.get(opts, :temperature, @default_temperature)
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)

    # Validate temperature is in recommended range
    validated_temperature =
      if temperature < 0.2 or temperature > 0.4 do
        Logger.warning(
          "Temperature #{temperature} outside recommended range (0.2-0.4), using #{@default_temperature}"
        )

        @default_temperature
      else
        temperature
      end

    # Parse model string to extract provider and model name
    {provider, model_name} = infer_provider(model_string)

    model = %Model{
      provider: provider,
      model: model_name,
      temperature: validated_temperature,
      max_tokens: max_tokens
    }

    {:ok, model}
  rescue
    error ->
      {:error, "Failed to build model: #{inspect(error)}"}
  end

  @spec infer_provider(String.t()) :: {atom(), String.t()}
  defp infer_provider("gpt-" <> _ = model), do: {:openai, model}
  defp infer_provider("claude-" <> _ = model), do: {:anthropic, model}
  defp infer_provider("gemini-" <> _ = model), do: {:google, model}

  defp infer_provider(model) do
    case String.split(model, "/", parts: 2) do
      [provider_str, model_str] -> {String.to_atom(provider_str), model_str}
      [single_part] -> {:openai, single_part}
    end
  end

  @spec generate_reasoning(Prompt.t(), Model.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  defp generate_reasoning(prompt, model, _opts) do
    completion_params = %{
      model: model,
      prompt: prompt,
      temperature: model.temperature,
      max_tokens: model.max_tokens
    }

    case TextCompletion.run(completion_params, %{}) do
      {:ok, %{content: content}} ->
        {:ok, content}

      {:ok, %{content: content}, _meta} ->
        {:ok, content}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec extract_list_items(String.t(), Regex.t()) :: list(String.t())
  defp extract_list_items(text, header_pattern) do
    # Find the section that matches the header pattern
    # Capture everything after the header until we hit a double newline or end
    case Regex.run(~r/#{Regex.source(header_pattern)}[:\s]*\n?(.*?)(?:\n\n|\z)/is, text) do
      [_, content] ->
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&bullet_point?/1)
        |> Enum.map(&clean_bullet_point/1)
        |> Enum.reject(&(&1 == ""))

      nil ->
        []
    end
  end

  @spec extract_approach(String.t()) :: String.t() | nil
  defp extract_approach(text) do
    # Look for the overall approach description
    case Regex.run(~r/(?:approach|strategy)[:\s]+([^\n]+)/i, text) do
      [_, approach] -> String.trim(approach)
      nil -> nil
    end
  end

  @spec extract_code_blocks(String.t()) :: list(String.t())
  defp extract_code_blocks(text) do
    Regex.scan(~r/```(?:\w+)?\n(.*?)```/s, text)
    |> Enum.map(fn [_, code] -> String.trim(code) end)
  end

  @spec filter_bullet_points(list(String.t())) :: list(String.t())
  defp filter_bullet_points(lines) do
    lines
    |> Enum.filter(&bullet_point?/1)
    |> Enum.map(&clean_bullet_point/1)
    |> Enum.reject(&(&1 == "" or String.length(&1) < 5))
  end

  @spec bullet_point?(String.t()) :: boolean()
  defp bullet_point?(line) do
    trimmed = String.trim(line)
    String.match?(trimmed, ~r/^[\-\*\•]\s+|^\d+\.\s+/)
  end

  @spec clean_bullet_point(String.t()) :: String.t()
  defp clean_bullet_point(line) do
    line
    |> String.trim()
    |> String.replace(~r/^[\-\*\•]\s+|^\d+\.\s+/, "")
    |> String.trim()
  end
end
