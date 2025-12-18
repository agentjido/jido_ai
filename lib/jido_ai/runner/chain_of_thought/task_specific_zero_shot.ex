defmodule Jido.AI.Runner.ChainOfThought.TaskSpecificZeroShot do
  @moduledoc """
  Task-specific zero-shot Chain-of-Thought reasoning variants.

  This module implements specialized zero-shot CoT patterns optimized for
  different task categories. Each variant uses domain-specific prompts and
  reasoning structures tailored to the task type.

  ## Supported Task Types

  - `:mathematical` - Mathematical reasoning with step-by-step calculations
  - `:debugging` - Error analysis and root cause identification
  - `:workflow` - Multi-action orchestration and sequencing
  - Custom types via registration

  ## Mathematical Reasoning

  Optimized for calculation-heavy tasks with emphasis on:
  - Breaking down complex calculations
  - Showing intermediate steps
  - Verifying results
  - Identifying arithmetic/logic errors

  ## Debugging Reasoning

  Optimized for error diagnosis with emphasis on:
  - Understanding error context
  - Analyzing stack traces
  - Identifying root causes
  - Proposing fixes

  ## Workflow Reasoning

  Optimized for multi-step orchestration with emphasis on:
  - Action dependencies
  - Sequencing constraints
  - Resource management
  - Error handling between steps

  ## Usage

      # Mathematical reasoning
      {:ok, reasoning} = TaskSpecificZeroShot.generate(
        problem: "Calculate the area of a circle with radius 5",
        task_type: :mathematical,
        temperature: 0.3
      )

      # Debugging reasoning
      {:ok, reasoning} = TaskSpecificZeroShot.generate(
        problem: "Fix this error: undefined function foo/1",
        task_type: :debugging,
        context: %{error: "...", stacktrace: "..."}
      )

      # Workflow reasoning
      {:ok, reasoning} = TaskSpecificZeroShot.generate(
        problem: "Process user signup with email verification",
        task_type: :workflow
      )

      # Custom task type
      TaskSpecificZeroShot.register_task_type(:custom, %{
        prompt_template: "...",
        section_patterns: %{}
      })

  ## Temperature Guidelines

  - 0.2-0.3: Focused, deterministic reasoning (recommended for math/debugging)
  - 0.3-0.4: Balanced creativity and consistency (workflow)
  - Higher: More exploratory (use with caution)
  """

  require Logger
  alias Jido.AI.Actions.TextCompletion
  alias Jido.AI.{Model, Prompt}

  @default_temperature 0.3
  @default_max_tokens 2000

  # Store for custom task types
  @custom_task_types :task_specific_zero_shot_custom_types

  @doc """
  Generates task-specific zero-shot CoT reasoning.

  Uses specialized prompts and reasoning structures optimized for
  the specified task type.

  ## Parameters

  - `opts` - Keyword list with options:
    - `:problem` (required) - The problem or task description
    - `:task_type` (required) - Task type (:mathematical, :debugging, :workflow, or custom)
    - `:model` - Model string (default: "gpt-4o")
    - `:temperature` - Temperature for generation (default: 0.3)
    - `:max_tokens` - Maximum tokens in response (default: 2000)
    - `:context` - Additional context (default: %{})

  ## Returns

  - `{:ok, reasoning}` - Task-specific reasoning map
  - `{:error, reason}` - Generation failed

  ## Examples

      {:ok, reasoning} = TaskSpecificZeroShot.generate(
        problem: "What is 15% of 240?",
        task_type: :mathematical
      )

      {:ok, reasoning} = TaskSpecificZeroShot.generate(
        problem: "Why does this function crash?",
        task_type: :debugging,
        context: %{error: "FunctionClauseError", code: "..."}
      )
  """
  @spec generate(keyword()) :: {:ok, map()} | {:error, term()}
  def generate(opts) do
    with {:ok, problem} <- validate_problem(opts),
         {:ok, task_type} <- validate_task_type(opts),
         {:ok, prompt} <- build_task_specific_prompt(problem, task_type, opts),
         {:ok, model} <- build_model(opts),
         {:ok, response} <- generate_reasoning(prompt, model, opts),
         {:ok, parsed} <- parse_task_specific_reasoning(response, problem, task_type) do
      {:ok, parsed}
    else
      {:error, reason} = error ->
        Logger.error("Task-specific zero-shot reasoning generation failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Builds a task-specific prompt optimized for the given task type.

  ## Parameters

  - `problem` - The problem or task description
  - `task_type` - Task type atom
  - `opts` - Additional options for prompt customization

  ## Returns

  - `{:ok, prompt}` - Jido.AI.Prompt struct
  - `{:error, reason}` - Prompt building failed
  """
  @spec build_task_specific_prompt(String.t(), atom(), keyword()) ::
          {:ok, Prompt.t()} | {:error, term()}
  def build_task_specific_prompt(problem, task_type, opts \\ []) do
    context = Keyword.get(opts, :context, %{})
    task_guidance = get_task_guidance(task_type)

    template = """
    #{format_context(context)}Problem: #{problem}

    #{task_guidance}

    Let's think step by step to solve this problem.
    """

    prompt = Prompt.new(:user, String.trim(template))
    {:ok, prompt}
  end

  @doc """
  Parses task-specific LLM response into structured reasoning.

  Extracts reasoning steps and task-specific components based on
  the task type.

  ## Parameters

  - `response_text` - Raw LLM response text
  - `problem` - Original problem statement
  - `task_type` - Task type atom

  ## Returns

  - `{:ok, reasoning}` - Task-specific reasoning map
  - `{:error, reason}` - Parsing failed
  """
  @spec parse_task_specific_reasoning(String.t(), String.t(), atom()) ::
          {:ok, map()} | {:error, term()}
  def parse_task_specific_reasoning(response_text, problem, task_type) do
    # Extract common components
    steps = extract_steps(response_text)
    answer = extract_answer(response_text, steps)

    # Extract task-specific components
    task_specific = extract_task_specific_components(response_text, task_type)

    reasoning = %{
      problem: problem,
      task_type: task_type,
      reasoning_text: response_text,
      steps: steps,
      answer: answer,
      task_specific: task_specific,
      timestamp: DateTime.utc_now()
    }

    {:ok, reasoning}
  end

  @doc """
  Registers a custom task type with domain-specific configuration.

  ## Parameters

  - `task_type` - Atom identifier for the task type
  - `config` - Configuration map with:
    - `:guidance` - Guidance text for the task type
    - `:extractors` (optional) - Custom extraction functions

  ## Returns

  - `:ok`

  ## Examples

      TaskSpecificZeroShot.register_task_type(:optimization, %{
        guidance: \"\"\"
        Focus on:
        - Identifying performance bottlenecks
        - Analyzing time/space complexity
        - Proposing optimization strategies
        - Measuring improvement potential
        \"\"\"
      })
  """
  @spec register_task_type(atom(), map()) :: :ok
  def register_task_type(task_type, config) when is_atom(task_type) and is_map(config) do
    table = get_or_create_ets_table()
    :ets.insert(table, {task_type, config})
    :ok
  end

  @doc """
  Gets the configuration for a registered task type.

  ## Parameters

  - `task_type` - Atom identifier for the task type

  ## Returns

  - `{:ok, config}` - Task type configuration
  - `{:error, :not_found}` - Task type not registered
  """
  @spec get_task_type_config(atom()) :: {:ok, map()} | {:error, :not_found}
  def get_task_type_config(task_type) do
    case :ets.whereis(@custom_task_types) do
      :undefined ->
        {:error, :not_found}

      table ->
        case :ets.lookup(table, task_type) do
          [{^task_type, config}] -> {:ok, config}
          [] -> {:error, :not_found}
        end
    end
  end

  @doc """
  Lists all registered custom task types.

  ## Returns

  List of registered task type atoms
  """
  @spec list_custom_task_types() :: list(atom())
  def list_custom_task_types do
    case :ets.whereis(@custom_task_types) do
      :undefined ->
        []

      table ->
        :ets.tab2list(table)
        |> Enum.map(fn {task_type, _config} -> task_type end)
    end
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

  @spec validate_task_type(keyword()) :: {:ok, atom()} | {:error, term()}
  defp validate_task_type(opts) do
    case Keyword.get(opts, :task_type) do
      nil ->
        {:error, "Task type is required"}

      task_type when is_atom(task_type) ->
        if valid_task_type?(task_type) do
          {:ok, task_type}
        else
          {:error, "Invalid task type: #{task_type}"}
        end

      _ ->
        {:error, "Task type must be an atom"}
    end
  end

  @spec valid_task_type?(atom()) :: boolean()
  defp valid_task_type?(task_type) do
    task_type in [:mathematical, :debugging, :workflow] or
      match?({:ok, _}, get_task_type_config(task_type))
  end

  @spec get_task_guidance(atom()) :: String.t()
  defp get_task_guidance(:mathematical) do
    """
    Task Type: Mathematical Reasoning

    Focus on:
    - Breaking down the calculation into clear steps
    - Showing all intermediate results
    - Explaining the mathematical operations used
    - Verifying the final answer
    - Identifying any units or conversions needed

    Show your calculations step by step, making sure each step follows logically
    from the previous one.
    """
  end

  defp get_task_guidance(:debugging) do
    """
    Task Type: Debugging

    Focus on:
    - Understanding the error message and context
    - Analyzing what the code is trying to do
    - Identifying where things go wrong
    - Finding the root cause (not just symptoms)
    - Proposing a fix that addresses the root cause
    - Considering edge cases that might trigger the error

    Think systematically about what could cause this error and why.
    """
  end

  defp get_task_guidance(:workflow) do
    """
    Task Type: Workflow Orchestration

    Focus on:
    - Identifying all required actions/steps
    - Determining dependencies between steps
    - Defining the correct execution order
    - Handling potential errors at each step
    - Managing resources and state across steps
    - Considering rollback or compensation strategies

    Think through the complete workflow from start to finish, including error scenarios.
    """
  end

  defp get_task_guidance(custom_type) do
    case get_task_type_config(custom_type) do
      {:ok, %{guidance: guidance}} ->
        """
        Task Type: #{custom_type |> Atom.to_string() |> String.capitalize()}

        #{guidance}
        """

      {:error, :not_found} ->
        # Fallback to generic guidance
        """
        Task Type: General

        Think step by step to solve this problem systematically.
        """
    end
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

    # Parse model string to extract provider and model name
    {provider, model_name} = infer_provider(model_string)

    model = %Model{
      provider: provider,
      model: model_name,
      temperature: temperature,
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

  @spec extract_steps(String.t()) :: list(String.t())
  defp extract_steps(text) do
    text
    |> String.split("\n")
    |> Enum.filter(&step?/1)
    |> Enum.map(&clean_step/1)
    |> Enum.reject(&(&1 == ""))
  end

  @spec step?(String.t()) :: boolean()
  defp step?(line) do
    trimmed = String.trim(line)

    (String.match?(trimmed, ~r/^\d+[\.\)]\s+/) or
       String.match?(trimmed, ~r/^Step\s+\d+/i) or
       String.match?(trimmed, ~r/^[\-\*]\s+/) or
       String.match?(trimmed, ~r/^(First|Then|Next|Finally),/i)) and
      String.length(trimmed) > 5
  end

  @spec clean_step(String.t()) :: String.t()
  defp clean_step(line) do
    line
    |> String.trim()
    |> String.replace(~r/^\d+[\.\)]\s+/, "")
    |> String.replace(~r/^Step\s+\d+:\s*/i, "")
    |> String.replace(~r/^[\-\*]\s+/, "")
    |> String.replace(~r/^(First|Then|Next|Finally),\s*/i, "")
    |> String.trim()
  end

  @spec extract_answer(String.t(), list(String.t())) :: String.t() | nil
  defp extract_answer(text, steps) do
    # Try specific answer patterns first (most specific to least specific)
    answer_patterns = [
      # Match "answer is" explicitly (allow periods for decimals)
      ~r/(?:the )?(?:final )?answer is:?\s+([^\n,]+?)\.?\s*$/im,
      # Match "so answer is"
      ~r/\bso,?\s+(?:the )?answer is\s+([^\n,]+?)\.?\s*$/im,
      # Match result/solution
      ~r/(?:result|solution):\s*([^\n,]+?)\.?\s*$/im,
      # Match therefore/thus
      ~r/\b(?:therefore|thus),?\s+.*?(\d+(?:\.\d+)?(?:\s+\w+)?)\s*\.?\s*$/im
    ]

    # Find first matching pattern
    answer =
      Enum.find_value(answer_patterns, fn pattern ->
        case Regex.run(pattern, text) do
          [_, captured] -> String.trim(captured)
          _ -> nil
        end
      end)

    answer || List.last(steps)
  end

  @spec extract_task_specific_components(String.t(), atom()) :: map()
  defp extract_task_specific_components(text, :mathematical) do
    %{
      calculations: extract_calculations(text),
      intermediate_results: extract_intermediate_results(text),
      verification: extract_verification(text)
    }
  end

  defp extract_task_specific_components(text, :debugging) do
    %{
      error_analysis: extract_error_analysis(text),
      root_cause: extract_root_cause(text),
      proposed_fix: extract_proposed_fix(text)
    }
  end

  defp extract_task_specific_components(text, :workflow) do
    %{
      actions: extract_actions(text),
      dependencies: extract_dependencies(text),
      error_handling: extract_error_handling(text)
    }
  end

  defp extract_task_specific_components(_text, _custom_type) do
    # For custom types, return empty map or use custom extractors if defined
    %{}
  end

  # Mathematical-specific extractors

  @spec extract_calculations(String.t()) :: list(String.t())
  defp extract_calculations(text) do
    # Extract lines that look like calculations (contain =, *, /, +, -, etc.)
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.match?(&1, ~r/[\d\w\s]+[=\+\-\*\/÷×]\s*[\d\w]/))
    |> Enum.reject(&(&1 == ""))
  end

  @spec extract_intermediate_results(String.t()) :: list(String.t())
  defp extract_intermediate_results(text) do
    # Extract lines with intermediate results
    Regex.scan(~r/=\s*([^\n]+)/i, text)
    |> Enum.map(fn [_, result] -> String.trim(result) end)
    |> Enum.reject(&(&1 == ""))
  end

  @spec extract_verification(String.t()) :: String.t() | nil
  defp extract_verification(text) do
    # Look for verification or check steps
    case Regex.run(~r/(verif\w*|check\w*)[:\s]+([^\n]+)/i, text) do
      [_, _, verification] -> String.trim(verification)
      _ -> nil
    end
  end

  # Debugging-specific extractors

  @spec extract_error_analysis(String.t()) :: String.t() | nil
  defp extract_error_analysis(text) do
    case Regex.run(~r/(error|exception|failure)[:\s]+([^\n]+)/i, text) do
      [_, _, analysis] -> String.trim(analysis)
      _ -> nil
    end
  end

  @spec extract_root_cause(String.t()) :: String.t() | nil
  defp extract_root_cause(text) do
    # Try multiple patterns to find root cause (most specific first)
    patterns = [
      # Try "because" first as it's usually more specific
      ~r/\bbecause\s+(?:of\s+)?([^\n\.]+)/i,
      # Then explicit labels
      ~r/\b(root cause):\s+([^\n]+)/i,
      ~r/\b(reason):\s+([^\n]+)/i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, text) do
        [_, captured] -> String.trim(captured)
        [_, _, captured] -> String.trim(captured)
        _ -> nil
      end
    end)
  end

  @spec extract_proposed_fix(String.t()) :: String.t() | nil
  defp extract_proposed_fix(text) do
    case Regex.run(~r/\b(fix|solution):\s+([^\n]+)/i, text) do
      [_, _, fix] -> String.trim(fix)
      _ -> nil
    end
  end

  # Workflow-specific extractors

  @spec extract_actions(String.t()) :: list(String.t())
  defp extract_actions(text) do
    # Extract actions using same logic as step extraction
    extract_steps(text)
  end

  @spec extract_dependencies(String.t()) :: list(String.t())
  defp extract_dependencies(text) do
    # Look for dependency indicators like "after", "depends on", "requires"
    Regex.scan(~r/(after|depends on|requires)[:\s]+([^\n]+)/i, text)
    |> Enum.map(fn [_, _, dep] -> String.trim(dep) end)
    |> Enum.reject(&(&1 == ""))
  end

  @spec extract_error_handling(String.t()) :: list(String.t())
  defp extract_error_handling(text) do
    # Look for error handling patterns
    Regex.scan(~r/(if.*fails?|on error|fallback|rollback)[:\s]*([^\n]+)/i, text)
    |> Enum.map(fn
      [_, _, handling] -> String.trim(handling)
      [match] -> String.trim(match)
    end)
    |> Enum.reject(&(&1 == ""))
  end

  @spec get_or_create_ets_table() :: :ets.table()
  defp get_or_create_ets_table do
    case :ets.whereis(@custom_task_types) do
      :undefined ->
        :ets.new(@custom_task_types, [:named_table, :public, :set])

      table ->
        table
    end
  end
end
