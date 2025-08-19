defmodule Jido.Eval.Metrics.Faithfulness do
  @moduledoc """
  Faithfulness metric for evaluating how grounded responses are in provided contexts.

  This metric measures whether the information in a response is supported by the 
  retrieved contexts. It uses an LLM to identify statements in the response and 
  check if each statement can be inferred from the given contexts.

  The metric returns a score between 0.0 and 1.0, where:
  - 1.0 = All statements in the response are fully supported by contexts
  - 0.0 = No statements in the response are supported by contexts

  ## Algorithm

  1. Extract individual statements/claims from the response
  2. For each statement, check if it can be attributed to the contexts
  3. Calculate faithfulness as: (supported_statements / total_statements)

  ## Required Fields

  - `:response` - The AI system's response to evaluate
  - `:retrieved_contexts` - List of context documents used for generation

  ## Examples

      # High faithfulness - response supported by context
      sample = %SingleTurn{
        response: "Paris is the capital of France.",
        retrieved_contexts: ["France's capital city is Paris, located in northern France."]
      }
      {:ok, 1.0} = Faithfulness.evaluate(sample, config, [])

      # Low faithfulness - response not supported  
      sample = %SingleTurn{
        response: "London is the capital of France.", 
        retrieved_contexts: ["France's capital city is Paris, located in northern France."]
      }
      {:ok, 0.0} = Faithfulness.evaluate(sample, config, [])

  ## Configuration

  Uses the configured LLM model from `config.llm` for statement analysis.
  Supports timeout configuration via opts: `[timeout: 30_000]`
  """

  @behaviour Jido.Eval.Metric

  alias Jido.Eval.Metrics.Utils
  alias Jido.Eval.Sample.SingleTurn

  require Logger

  # LLM prompts for faithfulness evaluation
  @statement_extraction_prompt """
  Given the following response, extract all the individual claims or statements that can be fact-checked.
  Return each statement on a separate line, numbered.

  Response: {{response}}

  Statements:
  """

  @faithfulness_check_prompt """
  Given the following contexts and a statement, determine if the statement can be attributed to or inferred from the contexts.
  Answer with only "YES" if the statement is supported, or "NO" if it is not supported.

  Contexts:
  {{contexts}}

  Statement: {{statement}}

  Answer:
  """

  @impl true
  def name, do: "Faithfulness"

  @impl true
  def description do
    "Measures how grounded the response is in the provided contexts by checking if " <>
      "all statements in the response can be attributed to the given contexts"
  end

  @impl true
  def required_fields, do: [:response, :retrieved_contexts]

  @impl true
  def sample_types, do: [:single_turn]

  @impl true
  def score_range, do: {0.0, 1.0}

  @impl true
  def evaluate(%SingleTurn{} = sample, config, opts) do
    Logger.debug("Starting faithfulness evaluation")

    with :ok <- Jido.Eval.Metric.validate_sample(sample, __MODULE__),
         {:ok, statements} <- extract_statements(sample.response, config, opts),
         {:ok, faithfulness_score} <-
           check_statements_faithfulness(statements, sample.retrieved_contexts, config, opts) do
      Logger.debug("Faithfulness evaluation completed with score: #{faithfulness_score}")
      {:ok, faithfulness_score}
    else
      {:error, reason} ->
        Logger.warning("Faithfulness evaluation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def evaluate(sample, _config, _opts) do
    sample_type = Jido.Eval.Metric.get_sample_type(sample)
    {:error, {:invalid_sample_type, sample_type}}
  end

  # Private functions

  defp extract_statements(response, config, opts) do
    prompt = Utils.build_prompt(@statement_extraction_prompt, %{response: response})

    case Utils.execute_llm_metric("Faithfulness", config.model_spec, prompt, opts) do
      {:ok, llm_response} ->
        statements = parse_statements(llm_response)

        if Enum.empty?(statements) do
          Logger.warning("No statements extracted from response: #{response}")
          # If no statements can be extracted, assume the response itself is the statement
          {:ok, [response]}
        else
          {:ok, statements}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_statements(llm_response) do
    llm_response
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(fn line ->
      # Keep lines that start with numbers or have content
      String.match?(line, ~r/^\d+\.?\s+.+/) or
        (String.length(line) > 0 and not String.match?(line, ~r/^statements?:?$/i))
    end)
    |> Enum.map(fn line ->
      # Remove numbering (e.g., "1. " or "1) ")
      String.replace(line, ~r/^\d+[.)]\s*/, "")
    end)
    |> Enum.filter(fn statement -> String.length(statement) > 0 end)
  end

  defp check_statements_faithfulness(statements, contexts, config, opts) do
    if Enum.empty?(statements) do
      {:ok, 0.0}
    else
      formatted_contexts = Utils.format_contexts(contexts)

      # Check each statement against contexts
      results =
        statements
        |> Task.async_stream(
          fn statement ->
            check_single_statement(statement, formatted_contexts, config, opts)
          end,
          timeout: Keyword.get(opts, :timeout, 30_000),
          max_concurrency: 3
        )
        |> Enum.to_list()

      # Process results
      case collect_results(results) do
        {:ok, supported_count} ->
          faithfulness = supported_count / length(statements)
          {:ok, faithfulness}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp check_single_statement(statement, formatted_contexts, config, opts) do
    prompt =
      Utils.build_prompt(@faithfulness_check_prompt, %{
        contexts: formatted_contexts,
        statement: statement
      })

    case Utils.execute_llm_metric("Faithfulness", config.model_spec, prompt, opts) do
      {:ok, llm_response} ->
        case Utils.parse_boolean(llm_response) do
          {:ok, is_supported} ->
            {:ok, is_supported}

          {:error, _} ->
            # Fallback: if we can't parse, assume not supported
            Logger.debug(
              "Could not parse faithfulness response, assuming not supported: #{llm_response}"
            )

            {:ok, false}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp collect_results(results) do
    case Enum.find(results, fn
           {:exit, _} -> true
           {:ok, {:error, _}} -> true
           _ -> false
         end) do
      nil ->
        supported_count =
          results
          |> Enum.count(fn {:ok, {:ok, is_supported}} -> is_supported end)

        {:ok, supported_count}

      {:exit, reason} ->
        {:error, {:timeout, reason}}

      {:ok, {:error, reason}} ->
        {:error, reason}
    end
  end
end
