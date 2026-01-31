defmodule Jido.AI do
  @moduledoc """
  AI integration layer for the Jido ecosystem.

  Jido.AI provides a unified interface for AI interactions, built on ReqLLM and
  integrated with the Jido action framework.

  ## Features

  - Accuracy improvement via self-consistency (multiple candidates + aggregation)
  - Prompt evaluation with GEPA (accuracy, cost, latency metrics)
  - Model aliases for semantic model references
  - Action-based AI workflows
  - Splode-based error handling

  ## Model Aliases

  Use semantic model aliases instead of hardcoded model strings:

      Jido.AI.resolve_model(:fast)      # => "anthropic:claude-haiku-4-5"
      Jido.AI.resolve_model(:capable)   # => "anthropic:claude-sonnet-4-20250514"

  Configure custom aliases in your config:

      config :jido_ai,
        model_aliases: %{
          fast: "anthropic:claude-haiku-4-5",
          capable: "anthropic:claude-sonnet-4-20250514"
        }

  ## Accuracy Improvement

  Generate multiple candidates and select the best via aggregation:

      {:ok, best, metadata} = Jido.AI.improve_accuracy("What is 15 * 23?")
      # best.content => "345"
      # metadata.confidence => 0.6

      # With Chain-of-Thought reasoning
      {:ok, best, metadata} = Jido.AI.improve_accuracy("Solve: 15 * 23 + 7",
        reasoning: true,
        num_candidates: 7
      )

  ## Prompt Evaluation (GEPA)

  Evaluate prompt templates against test tasks:

      tasks = [
        %{input: "What is 2+2?", expected: "4"},
        %{input: "What is 3+3?", expected: "6"}
      ]

      {:ok, result} = Jido.AI.evaluate_prompt("Answer concisely: {{input}}", tasks)
      # result.accuracy => 0.75
      # result.token_cost => 150

  """

  alias Jido.AI.Accuracy.{Pipeline, Presets, SelfConsistency}
  alias Jido.AI.GEPA.{Evaluator, PromptVariant}
  alias Jido.AI.GEPA.Task, as: GEPATask

  @type model_alias :: :fast | :capable | :reasoning | :planning | atom()
  @type model_spec :: String.t()

  @default_aliases %{
    fast: "anthropic:claude-haiku-4-5",
    capable: "anthropic:claude-sonnet-4-20250514",
    reasoning: "anthropic:claude-sonnet-4-20250514",
    planning: "anthropic:claude-sonnet-4-20250514"
  }

  @doc """
  Returns all configured model aliases merged with defaults.

  ## Examples

      iex> aliases = Jido.AI.model_aliases()
      iex> aliases[:fast]
      "anthropic:claude-haiku-4-5"
  """
  @spec model_aliases() :: %{model_alias() => model_spec()}
  def model_aliases do
    configured = Application.get_env(:jido_ai, :model_aliases, %{})
    Map.merge(@default_aliases, configured)
  end

  @doc """
  Resolves a model alias or passes through a direct model spec.

  Model aliases are atoms like `:fast`, `:capable`, `:reasoning` that map
  to full ReqLLM model specifications. Direct model specs (strings) are
  passed through unchanged.

  ## Arguments

    * `model` - Either a model alias atom or a direct model spec string

  ## Returns

    A ReqLLM model specification string.

  ## Examples

      iex> Jido.AI.resolve_model(:fast)
      "anthropic:claude-haiku-4-5"

      iex> Jido.AI.resolve_model("openai:gpt-4")
      "openai:gpt-4"

      Jido.AI.resolve_model(:unknown_alias)
      # raises ArgumentError with unknown alias message
  """
  @spec resolve_model(model_alias() | model_spec()) :: model_spec()
  def resolve_model(model) when is_binary(model), do: model

  def resolve_model(model) when is_atom(model) do
    aliases = model_aliases()

    case Map.get(aliases, model) do
      nil ->
        raise ArgumentError,
              "Unknown model alias: #{inspect(model)}. " <>
                "Available aliases: #{inspect(Map.keys(aliases))}"

      spec ->
        spec
    end
  end

  # ============================================================================
  # Accuracy Improvement API
  # ============================================================================

  @doc """
  Improves response accuracy via self-consistency.

  Generates multiple candidate responses and selects the best one through
  aggregation (default: majority voting). This technique improves accuracy
  by sampling diverse responses and finding consensus.

  ## Options

  - `:reasoning` - Enable Chain-of-Thought reasoning (default: false)
  - `:num_candidates` - Number of candidates to generate (default: 5)
  - `:model` - Model to use (default: anthropic:claude-haiku-4-5)
  - `:aggregator` - Aggregation strategy: :majority_vote, :best_of_n, :weighted
  - `:temperature_range` - Temperature range for sampling (default: {0.0, 1.0})
  - `:timeout` - Per-candidate timeout in ms (default: 30_000)
  - `:max_concurrency` - Max parallel generations (default: 3)
  - `:system_prompt` - Optional system prompt

  ## Returns

  `{:ok, candidate, metadata}` where:
  - `candidate` - Best candidate with `:content` (and `:reasoning` if enabled)
  - `metadata` - Map with `:confidence`, `:num_candidates`, `:total_tokens`

  ## Examples

      {:ok, best, meta} = Jido.AI.improve_accuracy("What is 15 * 23?")
      best.content  # => "345"
      meta.confidence  # => 0.6

      {:ok, best, meta} = Jido.AI.improve_accuracy("Solve: 15 * 23 + 7",
        reasoning: true,
        num_candidates: 7,
        model: :fast
      )
      best.reasoning  # => "Let me calculate step by step..."
      best.content  # => "352"

  """
  @spec improve_accuracy(String.t(), keyword()) ::
          {:ok, map(), map()} | {:error, term()}
  def improve_accuracy(prompt, opts \\ []) when is_binary(prompt) do
    {reasoning, opts} = Keyword.pop(opts, :reasoning, false)
    opts = resolve_model_opt(opts)

    if reasoning do
      SelfConsistency.run_with_reasoning(prompt, opts)
    else
      SelfConsistency.run(prompt, opts)
    end
  end

  @doc """
  Runs the full accuracy pipeline with a preset configuration.

  The pipeline orchestrates multiple stages: difficulty estimation, generation,
  verification, search, reflection, and calibration. Presets provide optimized
  configurations for different use cases.

  ## Presets

  | Preset      | Description                          | Stages                              |
  |-------------|--------------------------------------|-------------------------------------|
  | `:fast`     | Minimal compute, basic verification  | generation + calibration            |
  | `:balanced` | Moderate compute, full verification  | + difficulty + verification         |
  | `:accurate` | Maximum compute, all features        | + search + reflection               |
  | `:coding`   | Optimized for code correctness       | + RAG + code verifiers              |
  | `:research` | Optimized for factual QA             | + RAG + factuality verifier         |

  ## Options

  - `:preset` - Pipeline preset (default: :balanced)
  - `:generator` - Generator function `fn query, context -> {:ok, answer} end`
  - `:model` - Model for default generator (if no generator provided)
  - `:context` - Additional context map
  - `:timeout` - Overall timeout in ms (default: 60_000)

  ## Returns

  `{:ok, result}` where result contains:
  - `:answer` - Final answer (or nil if abstained)
  - `:confidence` - Confidence score [0-1]
  - `:action` - Routing action taken (:direct, :with_verification, :abstain)
  - `:trace` - Stage execution trace
  - `:metadata` - Execution metadata

  ## Examples

      # With default generator
      {:ok, result} = Jido.AI.run_pipeline("What is 2+2?", model: :fast)
      result.answer  # => "4"
      result.confidence  # => 0.85

      # With preset
      {:ok, result} = Jido.AI.run_pipeline("Solve: 15 * 23",
        preset: :accurate,
        model: :capable
      )

      # With custom generator
      {:ok, result} = Jido.AI.run_pipeline("What is 2+2?",
        preset: :balanced,
        generator: fn query, _ctx -> my_llm_call(query) end
      )

  """
  @spec run_pipeline(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_pipeline(query, opts \\ []) when is_binary(query) do
    preset = Keyword.get(opts, :preset, :balanced)
    generator = Keyword.get(opts, :generator) || build_default_generator(opts)
    context = Keyword.get(opts, :context, %{})
    timeout = Keyword.get(opts, :timeout, 60_000)

    with {:ok, config} <- Presets.get(preset),
         {:ok, pipeline} <- Pipeline.new(%{config: config}) do
      Pipeline.run(pipeline, query, generator: generator, context: context, timeout: timeout)
    end
  end

  @doc """
  Lists available accuracy pipeline presets.

  ## Examples

      Jido.AI.accuracy_presets()
      # => [:fast, :balanced, :accurate, :coding, :research]

  """
  @spec accuracy_presets() :: [atom()]
  def accuracy_presets, do: Presets.list()

  @doc """
  Gets the configuration for an accuracy preset.

  Useful for inspecting what stages and settings a preset uses.

  ## Examples

      {:ok, config} = Jido.AI.get_accuracy_preset(:balanced)
      config.stages  # => [:difficulty_estimation, :generation, :verification, :calibration]

  """
  @spec get_accuracy_preset(atom()) :: {:ok, map()} | {:error, :unknown_preset}
  def get_accuracy_preset(preset), do: Presets.get(preset)

  # ============================================================================
  # Prompt Evaluation API (GEPA)
  # ============================================================================

  @doc """
  Evaluates a prompt template against test tasks.

  Runs the prompt template against each task and measures accuracy,
  token cost, and latency. Useful for prompt optimization and A/B testing.

  ## Parameters

  - `template` - Prompt template with `{{input}}` placeholder
  - `tasks` - List of task maps with `:input` and optional `:expected`
  - `opts` - Options:
    - `:model` - Model to use (default: openai:gpt-4o-mini)
    - `:timeout` - Per-task timeout in ms (default: 30_000)
    - `:parallel` - Run tasks in parallel (default: false)

  ## Returns

  `{:ok, result}` where result contains:
  - `:accuracy` - Fraction of tasks that matched expected output
  - `:token_cost` - Total tokens used
  - `:latency_ms` - Average latency per task
  - `:results` - Per-task results with `:success`, `:output`, `:tokens`

  ## Examples

      tasks = [
        %{input: "What is 2+2?", expected: "4"},
        %{input: "What is 3+3?", expected: "6"}
      ]

      {:ok, result} = Jido.AI.evaluate_prompt("Answer concisely: {{input}}", tasks)
      result.accuracy  # => 0.5
      result.token_cost  # => 120

      # With custom model
      {:ok, result} = Jido.AI.evaluate_prompt(template, tasks,
        model: "anthropic:claude-haiku-4-5"
      )

  """
  @spec evaluate_prompt(String.t(), [map()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def evaluate_prompt(template, tasks, opts \\ []) when is_binary(template) and is_list(tasks) do
    model = Keyword.get(opts, :model, "openai:gpt-4o-mini")
    timeout = Keyword.get(opts, :timeout, 30_000)
    parallel = Keyword.get(opts, :parallel, false)

    variant = PromptVariant.new!(%{template: template})

    gepa_tasks =
      Enum.map(tasks, fn task ->
        GEPATask.new!(%{
          input: Map.get(task, :input) || task["input"],
          expected: Map.get(task, :expected) || task["expected"]
        })
      end)

    eval_opts = [
      runner: build_runner(model),
      timeout: timeout,
      parallel: parallel,
      runner_opts: [model: model]
    ]

    Evaluator.evaluate_variant(variant, gepa_tasks, eval_opts)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp resolve_model_opt(opts) do
    case Keyword.get(opts, :model) do
      nil -> opts
      model when is_atom(model) -> Keyword.put(opts, :model, resolve_model(model))
      model when is_binary(model) -> opts
    end
  end

  defp build_default_generator(opts) do
    model =
      case Keyword.get(opts, :model) do
        nil -> "anthropic:claude-haiku-4-5"
        m when is_atom(m) -> resolve_model(m)
        m when is_binary(m) -> m
      end

    fn query, _context ->
      messages = [%{role: "user", content: query}]

      case ReqLLM.Generation.generate_text(model, messages, []) do
        {:ok, response} -> {:ok, extract_output(response)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp build_runner(model) do
    fn prompt, _input, _opts ->
      messages = [%{role: "user", content: prompt}]

      case ReqLLM.Generation.generate_text(model, messages, []) do
        {:ok, response} ->
          output = extract_output(response)
          tokens = extract_tokens(response)
          {:ok, %{output: output, tokens: tokens}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp extract_output(%ReqLLM.Response{message: %{content: content}}) do
    content
    |> List.wrap()
    |> Enum.map_join("", fn
      %{text: text} when is_binary(text) -> text
      %{type: :text, text: text} -> text
      part when is_binary(part) -> part
      part -> Map.get(part, :text, "")
    end)
  end

  defp extract_output(response) when is_binary(response), do: response
  defp extract_output(_), do: ""

  defp extract_tokens(%ReqLLM.Response{usage: %{total_tokens: tokens}}), do: tokens
  defp extract_tokens(_), do: 0
end
