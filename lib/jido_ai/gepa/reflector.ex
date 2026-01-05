defmodule Jido.AI.GEPA.Reflector do
  @moduledoc """
  Analyzes evaluation failures and proposes prompt mutations using LLM-based reflection.

  The Reflector is the "intelligence" behind GEPA's genetic evolution. It uses the LLM
  itself to examine why tasks failed and suggest concrete improvements to the prompt.

  ## Usage

      # After evaluating a variant
      {:ok, eval_result} = Evaluator.evaluate_variant(variant, tasks, runner: runner)

      # Get mutations based on failures
      {:ok, children} = Reflector.mutate_prompt(variant, eval_result, runner: runner)

      # children is a list of new PromptVariant structs with improved templates

  ## Runner Function

  Like the Evaluator, the Reflector requires a `:runner` function for LLM calls:

      runner.(prompt, input, opts) -> {:ok, %{output: String.t(), tokens: integer()}}

  This allows flexibility in which model is used for reflection (often a more capable
  model than the one being evaluated).

  ## Mutation Strategies

  The Reflector employs several mutation strategies:

  - **Textual**: Reword instructions, clarify ambiguities, add emphasis
  - **Structural**: Reorganize sections, add/remove examples, change format
  - **Crossover**: Combine successful elements from two parent prompts
  """

  alias Jido.AI.GEPA.PromptVariant

  @type reflection :: String.t()
  @type run_result :: Jido.AI.GEPA.Evaluator.run_result()

  @default_mutation_count 3
  @max_failure_samples 5

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Analyzes why tasks failed and produces natural language insights.

  ## Parameters

  - `variant` - The PromptVariant that was evaluated
  - `failing_results` - List of run_result maps where `success: false`
  - `opts` - Options:
    - `:runner` (required) - Function for LLM calls
    - `:runner_opts` - Additional options passed to runner

  ## Returns

  `{:ok, reflection_text}` with analysis, or `{:error, reason}`.

  ## Example

      failures = Enum.filter(eval_result.results, &(!&1.success))
      {:ok, reflection} = Reflector.reflect_on_failures(variant, failures, runner: runner)
  """
  @spec reflect_on_failures(PromptVariant.t(), [run_result()], keyword()) ::
          {:ok, reflection()} | {:error, atom()}
  def reflect_on_failures(%PromptVariant{} = variant, failing_results, opts)
      when is_list(failing_results) do
    case validate_opts(opts) do
      :ok ->
        if Enum.empty?(failing_results) do
          {:ok, "No failures to analyze. The prompt performed well on all tasks."}
        else
          do_reflect(variant, failing_results, opts)
        end

      {:error, _} = error ->
        error
    end
  end

  def reflect_on_failures(_, _, _), do: {:error, :invalid_args}

  @doc """
  Generates new prompt templates based on reflection analysis.

  ## Parameters

  - `variant` - The original PromptVariant
  - `reflection` - Analysis text from `reflect_on_failures/3`
  - `opts` - Options:
    - `:runner` (required) - Function for LLM calls
    - `:mutation_count` - Number of mutations to generate (default: 3)
    - `:runner_opts` - Additional options passed to runner

  ## Returns

  `{:ok, [template_strings]}` with new templates, or `{:error, reason}`.

  ## Example

      {:ok, templates} = Reflector.propose_mutations(variant, reflection, runner: runner)
      # templates is a list of 2-3 new prompt template strings
  """
  @spec propose_mutations(PromptVariant.t(), reflection(), keyword()) ::
          {:ok, [String.t()]} | {:error, atom()}
  def propose_mutations(%PromptVariant{} = variant, reflection, opts)
      when is_binary(reflection) do
    case validate_opts(opts) do
      :ok ->
        do_propose_mutations(variant, reflection, opts)

      {:error, _} = error ->
        error
    end
  end

  def propose_mutations(_, _, _), do: {:error, :invalid_args}

  @doc """
  Combined reflect + propose that returns new PromptVariant children.

  This is the main entry point for generating mutations after evaluation.

  ## Parameters

  - `variant` - The PromptVariant that was evaluated
  - `eval_result` - Full evaluation result from `Evaluator.evaluate_variant/3`
  - `opts` - Options:
    - `:runner` (required) - Function for LLM calls
    - `:mutation_count` - Number of mutations to generate (default: 3)
    - `:runner_opts` - Additional options passed to runner

  ## Returns

  `{:ok, [PromptVariant]}` with child variants, or `{:error, reason}`.

  ## Example

      {:ok, eval_result} = Evaluator.evaluate_variant(variant, tasks, runner: runner)
      {:ok, children} = Reflector.mutate_prompt(variant, eval_result, runner: runner)
  """
  @spec mutate_prompt(PromptVariant.t(), map(), keyword()) ::
          {:ok, [PromptVariant.t()]} | {:error, atom()}
  def mutate_prompt(%PromptVariant{} = variant, %{results: results} = _eval_result, opts)
      when is_list(results) do
    case validate_opts(opts) do
      :ok ->
        failing_results = Enum.filter(results, &(!&1.success))
        do_mutate_prompt(variant, failing_results, opts)

      {:error, _} = error ->
        error
    end
  end

  def mutate_prompt(_, _, _), do: {:error, :invalid_args}

  @doc """
  Combines elements from two parent prompts to create hybrid children.

  Crossover is a genetic algorithm technique that can discover novel
  combinations by merging successful elements from different variants.

  ## Parameters

  - `variant1` - First parent PromptVariant
  - `variant2` - Second parent PromptVariant
  - `opts` - Options:
    - `:runner` (required) - Function for LLM calls
    - `:children_count` - Number of children to generate (default: 2)
    - `:runner_opts` - Additional options passed to runner

  ## Returns

  `{:ok, [PromptVariant]}` with hybrid children, or `{:error, reason}`.

  ## Example

      {:ok, hybrids} = Reflector.crossover(variant_a, variant_b, runner: runner)
  """
  @spec crossover(PromptVariant.t(), PromptVariant.t(), keyword()) ::
          {:ok, [PromptVariant.t()]} | {:error, atom()}
  def crossover(%PromptVariant{} = variant1, %PromptVariant{} = variant2, opts) do
    case validate_opts(opts) do
      :ok ->
        do_crossover(variant1, variant2, opts)

      {:error, _} = error ->
        error
    end
  end

  def crossover(_, _, _), do: {:error, :invalid_args}

  # ============================================================================
  # Private Implementation
  # ============================================================================

  defp validate_opts(opts) do
    cond do
      not Keyword.has_key?(opts, :runner) -> {:error, :runner_required}
      not is_function(Keyword.get(opts, :runner), 3) -> {:error, :invalid_runner}
      true -> :ok
    end
  end

  defp do_reflect(variant, failing_results, opts) do
    runner = Keyword.fetch!(opts, :runner)
    runner_opts = Keyword.get(opts, :runner_opts, [])

    prompt = build_reflection_prompt(variant, failing_results)

    case runner.(prompt, "", runner_opts) do
      {:ok, %{output: output}} when is_binary(output) ->
        {:ok, String.trim(output)}

      {:ok, _} ->
        {:error, :invalid_runner_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_propose_mutations(variant, reflection, opts) do
    runner = Keyword.fetch!(opts, :runner)
    runner_opts = Keyword.get(opts, :runner_opts, [])
    mutation_count = Keyword.get(opts, :mutation_count, @default_mutation_count)

    prompt = build_mutation_prompt(variant, reflection, mutation_count)

    case runner.(prompt, "", runner_opts) do
      {:ok, %{output: output}} when is_binary(output) ->
        mutations = parse_mutations(output, mutation_count)
        {:ok, mutations}

      {:ok, _} ->
        {:error, :invalid_runner_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_mutate_prompt(variant, failing_results, opts) do
    # If no failures, return empty list (nothing to improve)
    if Enum.empty?(failing_results) do
      {:ok, []}
    else
      with {:ok, reflection} <- do_reflect(variant, failing_results, opts),
           {:ok, templates} <- do_propose_mutations(variant, reflection, opts) do
        children =
          templates
          |> Enum.map(&PromptVariant.create_child(variant, &1))

        {:ok, children}
      end
    end
  end

  defp do_crossover(variant1, variant2, opts) do
    runner = Keyword.fetch!(opts, :runner)
    runner_opts = Keyword.get(opts, :runner_opts, [])
    children_count = Keyword.get(opts, :children_count, 2)

    prompt = build_crossover_prompt(variant1, variant2, children_count)

    case runner.(prompt, "", runner_opts) do
      {:ok, %{output: output}} when is_binary(output) ->
        templates = parse_mutations(output, children_count)

        # Create children with both parents in lineage
        children =
          templates
          |> Enum.map(fn template ->
            # Use higher generation of the two parents
            gen = max(variant1.generation, variant2.generation) + 1

            PromptVariant.new!(%{
              template: template,
              generation: gen,
              parents: [variant1.id, variant2.id],
              metadata: %{mutation_type: :crossover}
            })
          end)

        {:ok, children}

      {:ok, _} ->
        {:error, :invalid_runner_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Prompt Building
  # ============================================================================

  defp build_reflection_prompt(variant, failing_results) do
    sampled_failures = Enum.take(failing_results, @max_failure_samples)

    failures_text =
      sampled_failures
      |> Enum.with_index(1)
      |> Enum.map(&format_failure/1)
      |> Enum.join("\n\n")

    template_text = format_template(variant.template)

    """
    You are analyzing a prompt that failed on some tasks. Your goal is to understand WHY it failed and identify patterns.

    ## Current Prompt Template

    #{template_text}

    ## Failed Tasks (#{length(sampled_failures)} of #{length(failing_results)} failures)

    #{failures_text}

    ## Analysis Request

    Analyze these failures and identify:
    1. Common patterns in why the prompt failed
    2. What the prompt is missing or doing wrong
    3. Specific weaknesses in the prompt's instructions

    Provide a concise analysis (2-4 paragraphs) focusing on actionable insights.
    """
  end

  defp build_mutation_prompt(variant, reflection, mutation_count) do
    template_text = format_template(variant.template)

    """
    You are improving a prompt based on failure analysis. Generate #{mutation_count} improved versions.

    ## Current Prompt Template

    #{template_text}

    ## Failure Analysis

    #{reflection}

    ## Mutation Request

    Generate exactly #{mutation_count} improved prompt templates. Each should address the identified issues differently:

    1. **Clarification**: Add clearer instructions or constraints
    2. **Restructuring**: Reorganize or reformat the prompt
    3. **Enhancement**: Add examples, context, or emphasis

    Format your response as:

    ---MUTATION 1---
    [Your improved prompt template here]

    ---MUTATION 2---
    [Your improved prompt template here]

    ---MUTATION 3---
    [Your improved prompt template here]

    Important:
    - Keep the {{input}} placeholder for the task input
    - Each mutation should be a complete, standalone prompt template
    - Focus on fixing the identified issues
    """
  end

  defp build_crossover_prompt(variant1, variant2, children_count) do
    template1 = format_template(variant1.template)
    template2 = format_template(variant2.template)

    """
    You are combining elements from two successful prompts to create hybrid versions.

    ## Parent Prompt A

    #{template1}

    ## Parent Prompt B

    #{template2}

    ## Crossover Request

    Create #{children_count} hybrid prompt templates that combine the best elements from both parents.
    Look for:
    - Effective phrasing from either parent
    - Structural elements that work well
    - Instructions or constraints that improve clarity

    Format your response as:

    ---MUTATION 1---
    [Your hybrid prompt template here]

    ---MUTATION 2---
    [Your hybrid prompt template here]

    Important:
    - Keep the {{input}} placeholder for the task input
    - Each hybrid should be a complete, standalone prompt template
    - Combine strengths from both parents rather than just concatenating
    """
  end

  # ============================================================================
  # Formatting Helpers
  # ============================================================================

  defp format_template(template) when is_binary(template) do
    "```\n#{template}\n```"
  end

  defp format_template(template) when is_map(template) do
    formatted =
      template
      |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
      |> Enum.join("\n")

    "```\n#{formatted}\n```"
  end

  defp format_template(template), do: inspect(template)

  defp format_failure({%{task: task, output: output, error: error}, index}) do
    expected =
      cond do
        task.expected -> "Expected: #{task.expected}"
        task.validator -> "Validator: custom function"
        true -> "No explicit criteria"
      end

    output_text =
      cond do
        error -> "Error: #{inspect(error)}"
        output -> "Output: #{truncate(output, 500)}"
        true -> "Output: (none)"
      end

    """
    ### Failure #{index}
    Input: #{truncate(task.input, 300)}
    #{expected}
    #{output_text}
    """
  end

  defp truncate(str, max_len) when is_binary(str) do
    if String.length(str) > max_len do
      String.slice(str, 0, max_len) <> "..."
    else
      str
    end
  end

  defp truncate(nil, _), do: "(nil)"
  defp truncate(other, _), do: inspect(other)

  # ============================================================================
  # Mutation Parsing
  # ============================================================================

  defp parse_mutations(output, expected_count) do
    # Try to parse mutations between ---MUTATION N--- markers
    pattern = ~r/---MUTATION \d+---\s*([\s\S]*?)(?=---MUTATION \d+---|$)/i

    mutations =
      Regex.scan(pattern, output)
      |> Enum.map(fn [_, content] -> String.trim(content) end)
      |> Enum.filter(&(String.length(&1) > 10))
      |> Enum.take(expected_count)

    # If we couldn't parse enough mutations, fall back to splitting by blank lines
    if length(mutations) < expected_count do
      fallback_parse(output, expected_count)
    else
      mutations
    end
  end

  defp fallback_parse(output, expected_count) do
    # Try splitting by double newlines and taking chunks that look like prompts
    output
    |> String.split(~r/\n{2,}/)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&looks_like_prompt?/1)
    |> Enum.take(expected_count)
  end

  defp looks_like_prompt?(text) do
    # A prompt should be reasonably long and contain common prompt elements
    String.length(text) > 20 and
      not String.starts_with?(text, "#") and
      not String.starts_with?(text, "```")
  end
end
