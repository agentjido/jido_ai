defmodule Jido.Eval.Metrics.ContextPrecision do
  @moduledoc """
  Context Precision metric for evaluating relevance of retrieved contexts to the user question.

  This metric measures how relevant the retrieved contexts are for answering the user's question.
  It uses an LLM to rate each context's relevance and computes precision based on the
  position of relevant contexts in the retrieval ranking.

  The metric returns a score between 0.0 and 1.0, where:
  - 1.0 = All retrieved contexts are relevant, with most relevant ones ranked first
  - 0.0 = No retrieved contexts are relevant to the question

  ## Algorithm

  1. For each retrieved context, determine if it's relevant to answering the question
  2. Calculate precision at each position based on relevant contexts seen so far
  3. Return average precision across all positions (Mean Average Precision)

  ## Required Fields

  - `:user_input` - The user's original question
  - `:retrieved_contexts` - List of context documents in retrieval order
  - `:reference` - The expected/ideal answer (used for relevance judgment)

  ## Examples

      # High precision - relevant contexts ranked first
      sample = %SingleTurn{
        user_input: "What is the capital of France?",
        retrieved_contexts: [
          "Paris is the capital and largest city of France.",
          "France is a country in Western Europe.", 
          "The Eiffel Tower is located in Paris."
        ],
        reference: "Paris is the capital of France."
      }
      {:ok, 1.0} = ContextPrecision.evaluate(sample, config, [])

      # Lower precision - irrelevant contexts mixed in
      sample = %SingleTurn{
        user_input: "What is the capital of France?",
        retrieved_contexts: [
          "Germany is a country in Central Europe.",  # irrelevant
          "Paris is the capital and largest city of France.",  # relevant
          "Spain shares a border with France."  # somewhat relevant
        ],
        reference: "Paris is the capital of France."
      }
      {:ok, 0.5} = ContextPrecision.evaluate(sample, config, [])

  ## Configuration

  Uses the configured LLM model from `config.llm` for relevance judgments.
  Supports timeout configuration via opts: `[timeout: 30_000]`
  """

  @behaviour Jido.Eval.Metric

  alias Jido.Eval.Metrics.Utils
  alias Jido.Eval.Sample.SingleTurn

  require Logger

  # LLM prompt for context relevance evaluation
  @relevance_check_prompt """
  Given a user question, a reference answer, and a context passage, determine if the context is relevant for answering the question.

  A context is relevant if it contains information that would help answer the user's question, even if it doesn't contain the complete answer.

  User Question: {{user_input}}

  Reference Answer: {{reference}}

  Context: {{context}}

  Is this context relevant for answering the user's question? Answer with only "YES" or "NO".

  Answer:
  """

  @impl true
  def name, do: "Context Precision"

  @impl true
  def description do
    "Measures the relevance of retrieved contexts to the user question by evaluating " <>
      "how many of the retrieved contexts are actually useful for answering the question"
  end

  @impl true
  def required_fields, do: [:user_input, :retrieved_contexts, :reference]

  @impl true
  def sample_types, do: [:single_turn]

  @impl true
  def score_range, do: {0.0, 1.0}

  @impl true
  def evaluate(%SingleTurn{} = sample, config, opts) do
    Logger.debug("Starting context precision evaluation")

    with :ok <- Jido.Eval.Metric.validate_sample(sample, __MODULE__),
         {:ok, relevance_scores} <- evaluate_context_relevance(sample, config, opts),
         {:ok, precision_score} <- calculate_precision(relevance_scores) do
      Logger.debug("Context precision evaluation completed with score: #{precision_score}")
      {:ok, precision_score}
    else
      {:error, reason} ->
        Logger.warning("Context precision evaluation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def evaluate(sample, _config, _opts) do
    sample_type = Jido.Eval.Metric.get_sample_type(sample)
    {:error, {:invalid_sample_type, sample_type}}
  end

  # Private functions

  defp evaluate_context_relevance(sample, config, opts) do
    contexts = sample.retrieved_contexts

    if Enum.empty?(contexts) do
      Logger.debug("No contexts provided, returning precision score of 0.0")
      {:ok, []}
    else
      # Evaluate each context for relevance
      results =
        contexts
        |> Enum.with_index()
        |> Task.async_stream(
          fn {context, index} ->
            {index, evaluate_single_context(sample, context, config, opts)}
          end,
          timeout: Keyword.get(opts, :timeout, 30_000),
          max_concurrency: 3
        )
        |> Enum.to_list()

      case collect_relevance_results(results) do
        {:ok, relevance_map} ->
          # Convert to ordered list by index
          relevance_scores =
            0..(length(contexts) - 1)
            |> Enum.map(fn index -> Map.get(relevance_map, index, false) end)

          {:ok, relevance_scores}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp evaluate_single_context(sample, context, config, opts) do
    prompt =
      Utils.build_prompt(@relevance_check_prompt, %{
        user_input: sample.user_input,
        reference: sample.reference,
        context: context
      })

    case Utils.execute_llm_metric("Context Precision", config.model_spec, prompt, opts) do
      {:ok, llm_response} ->
        case Utils.parse_boolean(llm_response) do
          {:ok, is_relevant} ->
            {:ok, is_relevant}

          {:error, _} ->
            # Fallback: if we can't parse, assume not relevant
            Logger.debug(
              "Could not parse context relevance response, assuming not relevant: #{llm_response}"
            )

            {:ok, false}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp collect_relevance_results(results) do
    case Enum.find(results, fn
           {:exit, _} -> true
           {:ok, {_index, {:error, _}}} -> true
           _ -> false
         end) do
      nil ->
        relevance_map =
          results
          |> Enum.into(%{}, fn {:ok, {index, {:ok, is_relevant}}} ->
            {index, is_relevant}
          end)

        {:ok, relevance_map}

      {:exit, reason} ->
        {:error, {:timeout, reason}}

      {:ok, {_index, {:error, reason}}} ->
        {:error, reason}
    end
  end

  defp calculate_precision(relevance_scores) do
    if Enum.empty?(relevance_scores) do
      {:ok, 0.0}
    else
      # Calculate precision at each position
      precisions =
        relevance_scores
        |> Enum.with_index(1)
        |> Enum.map(fn {is_relevant, position} ->
          if is_relevant do
            # Count relevant contexts up to this position
            relevant_count =
              relevance_scores
              |> Enum.take(position)
              |> Enum.count(& &1)

            relevant_count / position
          else
            0.0
          end
        end)

      # Return average precision (only consider positions where contexts are relevant)
      relevant_precisions = Enum.filter(precisions, fn p -> p > 0.0 end)

      average_precision =
        if Enum.empty?(relevant_precisions) do
          0.0
        else
          Enum.sum(relevant_precisions) / length(relevant_precisions)
        end

      {:ok, average_precision}
    end
  end
end
