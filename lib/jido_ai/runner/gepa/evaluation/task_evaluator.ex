defmodule Jido.AI.Runner.GEPA.Evaluation.TaskEvaluator do
  @moduledoc """
  Task-specific evaluation dispatcher for GEPA prompt optimization.

  This module implements task-specific evaluation strategies for different types of
  LLM tasks. It dispatches to the appropriate evaluator based on task type and falls
  back to generic evaluation when no specific evaluator is available.

  ## Supported Task Types

  - `:code_generation` - Code generation and programming tasks
  - `:reasoning` - Mathematical and logical reasoning tasks
  - `:classification` - Text classification tasks
  - `:question_answering` - Question answering tasks
  - `:summarization` - Text summarization tasks
  - Generic fallback for other types

  ## Usage

      # Evaluate with task-specific strategy
      result = TaskEvaluator.evaluate_prompt(
        "Write a function to calculate fibonacci",
        task: %{
          type: :code_generation,
          language: :elixir,
          test_cases: [%{input: 5, expected: 5}]
        }
      )

  ## Architecture

  The evaluator uses a strategy pattern:
  ```
  TaskEvaluator (dispatcher)
    ├─> CodeEvaluator (for :code_generation)
    ├─> ReasoningEvaluator (for :reasoning)
    ├─> ClassificationEvaluator (for :classification)
    ├─> QuestionAnsweringEvaluator (for :question_answering)
    ├─> SummarizationEvaluator (for :summarization)
    └─> Evaluator (generic fallback)
  ```
  """

  require Logger

  alias Jido.AI.Runner.GEPA.Evaluation.Strategies.ClassificationEvaluator
  alias Jido.AI.Runner.GEPA.Evaluation.Strategies.CodeEvaluator
  alias Jido.AI.Runner.GEPA.Evaluation.Strategies.QuestionAnsweringEvaluator
  alias Jido.AI.Runner.GEPA.Evaluation.Strategies.ReasoningEvaluator
  alias Jido.AI.Runner.GEPA.Evaluation.Strategies.SummarizationEvaluator
  alias Jido.AI.Runner.GEPA.Evaluator

  @type task_config :: map()
  @type prompt :: String.t()
  @type evaluation_result :: Evaluator.EvaluationResult.t()

  @doc """
  Evaluates a prompt using the appropriate task-specific evaluator.

  Dispatches to the correct evaluation strategy based on `task[:type]`.
  Falls back to generic evaluation if no specific evaluator is available.

  ## Parameters

  - `prompt` - The prompt to evaluate
  - `opts` - Evaluation options including task configuration

  ## Options

  - `:task` - Task configuration map (required)
    - `:type` - Task type atom (`:code_generation`, `:reasoning`, etc.)
    - Task-specific fields depend on type

  ## Examples

      # Code generation task
      TaskEvaluator.evaluate_prompt(
        "def fibonacci(n):",
        task: %{
          type: :code_generation,
          language: :python,
          test_cases: [%{input: 5, expected: 5}]
        }
      )

      # Fallback to generic for unknown type
      TaskEvaluator.evaluate_prompt(
        "Summarize this text",
        task: %{type: :unknown}
      )
  """
  @spec evaluate_prompt(prompt(), keyword()) :: {:ok, evaluation_result()} | {:error, term()}
  def evaluate_prompt(prompt, opts) when is_binary(prompt) and is_list(opts) do
    task = Keyword.get(opts, :task, %{})
    task_type = Map.get(task, :type, :generic)

    Logger.debug("Evaluating prompt with task type: #{task_type}")

    case dispatch_to_evaluator(task_type, prompt, opts) do
      {:ok, result} ->
        Logger.debug("Task evaluation completed (type: #{task_type}, fitness: #{result.fitness})")

        {:ok, result}

      {:error, reason} = error ->
        Logger.warning("Task evaluation failed (type: #{task_type}, reason: #{inspect(reason)})")

        error
    end
  end

  @doc """
  Evaluates multiple prompts in batch using task-specific evaluation.

  Similar to `evaluate_prompt/2` but handles multiple prompts with
  controlled concurrency.

  ## Examples

      TaskEvaluator.evaluate_batch(
        ["prompt 1", "prompt 2"],
        task: %{type: :code_generation, ...},
        parallelism: 5
      )
  """
  @spec evaluate_batch(list(prompt()), keyword()) :: list(evaluation_result())
  def evaluate_batch(prompts, opts) when is_list(prompts) and is_list(opts) do
    task = Keyword.get(opts, :task, %{})
    task_type = Map.get(task, :type, :generic)

    Logger.info("Batch evaluating #{length(prompts)} prompts (task type: #{task_type})")

    # Dispatch to appropriate evaluator
    case dispatch_to_batch_evaluator(task_type, prompts, opts) do
      results when is_list(results) ->
        successful = Enum.count(results, &is_nil(&1.error))
        Logger.info("Batch evaluation complete (#{successful}/#{length(prompts)} successful)")
        results

      error ->
        Logger.error("Batch evaluation failed: #{inspect(error)}")
        # Return error results for all prompts
        Enum.map(prompts, fn prompt ->
          %Evaluator.EvaluationResult{
            prompt: prompt,
            fitness: nil,
            error: :batch_evaluation_failed
          }
        end)
    end
  end

  # Private Functions

  @doc false
  @spec dispatch_to_evaluator(atom(), prompt(), keyword()) ::
          {:ok, evaluation_result()} | {:error, term()}
  defp dispatch_to_evaluator(:code_generation, prompt, opts) do
    # Use CodeEvaluator for code generation tasks
    CodeEvaluator.evaluate_prompt(prompt, opts)
  end

  defp dispatch_to_evaluator(:reasoning, prompt, opts) do
    # Use ReasoningEvaluator for reasoning tasks
    ReasoningEvaluator.evaluate_prompt(prompt, opts)
  end

  defp dispatch_to_evaluator(:classification, prompt, opts) do
    # Use ClassificationEvaluator for classification tasks
    ClassificationEvaluator.evaluate_prompt(prompt, opts)
  end

  defp dispatch_to_evaluator(:question_answering, prompt, opts) do
    # Use QuestionAnsweringEvaluator for QA tasks
    QuestionAnsweringEvaluator.evaluate_prompt(prompt, opts)
  end

  defp dispatch_to_evaluator(:summarization, prompt, opts) do
    # Use SummarizationEvaluator for summarization tasks
    SummarizationEvaluator.evaluate_prompt(prompt, opts)
  end

  defp dispatch_to_evaluator(_unknown_type, prompt, opts) do
    # Generic fallback for unknown task types
    Logger.debug("Unknown task type, using generic evaluator")
    Evaluator.evaluate_prompt(prompt, opts)
  end

  @doc false
  @spec dispatch_to_batch_evaluator(atom(), list(prompt()), keyword()) ::
          list(evaluation_result())
  defp dispatch_to_batch_evaluator(:code_generation, prompts, opts) do
    # Use CodeEvaluator batch evaluation
    CodeEvaluator.evaluate_batch(prompts, opts)
  end

  defp dispatch_to_batch_evaluator(_task_type, prompts, opts) do
    # For other types, use generic batch evaluation
    Evaluator.evaluate_batch(prompts, opts)
  end
end
