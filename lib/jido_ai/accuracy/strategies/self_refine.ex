defmodule Jido.AI.Accuracy.SelfRefine do
  @moduledoc """
  Single-pass self-refinement strategy for improving LLM responses.

  SelfRefine implements a lighter-weight refinement pattern compared to ReflectionLoop:
  - Single feedback + refinement pass (vs multiple iterations)
  - Lower latency and cost
  - Simpler API for basic improvement needs

  ## Workflow

  1. Generate initial response to prompt
  2. Generate self-feedback (critique of own response)
  3. Refine response based on feedback
  4. Return comparison showing improvement

  ## Configuration

  - `:model` - Model to use (default: from Config)
  - `:feedback_prompt` - Custom EEx template for feedback generation
  - `:refine_prompt` - Custom EEx template for refinement
  - `:temperature` - Temperature for generation (default: 0.7)
  - `:timeout` - Timeout for LLM calls in ms (default: 30_000)

  ## Usage

      # Create self-refine strategy with defaults
      strategy = SelfRefine.new!(%{})

      # Run self-refine on a prompt
      {:ok, result} = SelfRefine.run(strategy, "What is 15 * 23?")

      result.original_candidate    # Initial response
      result.feedback              # Self-critique
      result.refined_candidate     # Improved response
      result.comparison            # Improvement metrics

  ## Comparison with ReflectionLoop

  | Aspect | SelfRefine | ReflectionLoop |
  |--------|-----------|----------------|
  | Iterations | 1 | Multiple (configurable) |
  | Latency | Low | Higher |
  | Cost | Lower | Higher |
  | Use case | Quick improvement | Deep refinement |

  ## Prompts

  ### Feedback Prompt Template

  The default feedback prompt asks the model to:
  - Review its own response for issues
  - Identify specific weaknesses
  - Suggest concrete improvements

  Variables:
  - `@prompt` - The original question
  - `@response` - The model's own response

  ### Refine Prompt Template

  The default refine prompt asks the model to:
  - Incorporate the feedback
  - Fix identified issues
  - Provide an improved version

  Variables:
  - `@prompt` - The original question
  - `@response` - The original response
  - `@feedback` - The self-generated feedback

  ## Result Structure

  Returns a map with:
  - `:original_candidate` - Initial Candidate
  - `:feedback` - Self-critique text
  - `:refined_candidate` - Improved Candidate
  - `:comparison` - Improvement metrics

  """

  alias Jido.AI.Accuracy.{Candidate, Config}
  alias Jido.AI.Helpers.Text

  @type t :: %__MODULE__{
          model: String.t(),
          feedback_prompt: String.t() | nil,
          refine_prompt: String.t() | nil,
          temperature: number(),
          timeout: pos_integer()
        }

  @type result :: %{
          original_candidate: Candidate.t(),
          feedback: String.t(),
          refined_candidate: Candidate.t(),
          comparison: comparison()
        }

  @type comparison :: %{
          length_change: float(),
          length_delta: integer(),
          original_length: non_neg_integer(),
          refined_length: non_neg_integer(),
          improved: boolean()
        }

  defstruct [
    :model,
    feedback_prompt: nil,
    refine_prompt: nil,
    temperature: 0.7,
    timeout: 30_000
  ]

  @default_feedback_prompt """
  Review your own response to the following question for quality and correctness.

  Original Question: <%= @prompt %>

  === YOUR RESPONSE BEGINS ===
  <%= @response %>
  === YOUR RESPONSE ENDS ===

  Please analyze your response and provide:
  1. Any errors or inaccuracies you notice
  2. Areas that could be clearer or more complete
  3. Specific suggestions for improvement

  Be honest about any mistakes or weaknesses in your answer.
  """

  @default_refine_prompt """
  Based on the feedback below, provide an improved response to the original question.

  Original Question: <%= @prompt %>

  Your Original Response:
  <%= @response %>

  Feedback for Improvement:
  <%= @feedback %>

  Please provide a refined, improved response that addresses the feedback above.
  Focus on correcting errors and improving clarity.
  """

  @doc """
  Creates a new SelfRefine strategy from the given attributes.

  ## Options

  - `:model` - Model to use (defaults to Config.default_model())
  - `:feedback_prompt` - Custom EEx template for feedback generation
  - `:refine_prompt` - Custom EEx template for refinement
  - `:temperature` - Temperature for LLM (default: 0.7)
  - `:timeout` - Timeout in ms (default: 30_000)

  ## Returns

  - `{:ok, strategy}` - Success
  - `{:error, reason}` - Validation failed

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) do
    model = Keyword.get(opts, :model, Config.default_model())

    # Resolve model alias if atom
    resolved_model =
      case model do
        atom when is_atom(atom) -> Jido.AI.resolve_model(atom)
        binary when is_binary(binary) -> binary
      end

    with :ok <- validate_model(resolved_model),
         :ok <- validate_temperature(Keyword.get(opts, :temperature, 0.7)),
         :ok <- validate_timeout(Keyword.get(opts, :timeout, 30_000)) do
      strategy =
        struct(__MODULE__,
          model: resolved_model,
          feedback_prompt: Keyword.get(opts, :feedback_prompt),
          refine_prompt: Keyword.get(opts, :refine_prompt),
          temperature: Keyword.get(opts, :temperature, 0.7),
          timeout: Keyword.get(opts, :timeout, 30_000)
        )

      {:ok, strategy}
    end
  end

  @doc """
  Creates a new SelfRefine strategy, raising on error.

  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) do
    case new(opts) do
      {:ok, strategy} -> strategy
      {:error, reason} -> raise ArgumentError, "Invalid SelfRefine: #{format_error(reason)}"
    end
  end

  @doc """
  Runs the self-refine process on the given prompt.

  ## Process

  1. Generate initial response
  2. Generate self-feedback on the response
  3. Refine the response based on feedback
  4. Return comparison showing improvement

  ## Parameters

  - `strategy` - The SelfRefine strategy
  - `prompt` - The question/task to refine
  - `opts` - Additional options:
    - `:initial_candidate` - Skip initial generation, use this candidate
    - `:feedback` - Skip feedback generation, use this feedback
    - `:model` - Override model for this call
    - `:temperature` - Override temperature for this call

  ## Returns

  `{:ok, result}` where result contains:
  - `:original_candidate` - Initial response
  - `:feedback` - Self-critique
  - `:refined_candidate` - Improved response
  - `:comparison` - Improvement metrics

  ## Examples

      {:ok, result} = SelfRefine.run(strategy, "What is 15 * 23?")
      result.refined_candidate.content
      # => "15 × 23 = 345"

  """
  @spec run(t(), String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def run(%__MODULE__{} = strategy, prompt, opts \\ []) when is_binary(prompt) do
    with {:ok, original} <- get_or_generate_original(strategy, prompt, opts),
         {:ok, feedback} <- get_or_generate_feedback(strategy, prompt, original, opts),
         {:ok, refined} <- apply_refinement(strategy, prompt, original, feedback, opts) do
      comparison = compare_original_refined(original, refined)

      result = %{
        original_candidate: original,
        feedback: feedback,
        refined_candidate: refined,
        comparison: comparison
      }

      {:ok, result}
    end
  end

  @doc """
  Generates self-feedback for a response.

  ## Parameters

  - `strategy` - The SelfRefine strategy
  - `prompt` - The original question
  - `response` - The response to critique
  - `opts` - Additional options

  ## Returns

  `{:ok, feedback_text}` or `{:error, reason}`

  """
  @spec generate_feedback(t(), String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate_feedback(%__MODULE__{} = strategy, prompt, response, opts \\ [])
      when is_binary(prompt) and is_binary(response) do
    template = strategy.feedback_prompt || @default_feedback_prompt

    assigns = [
      prompt: prompt,
      response: truncate_content(response)
    ]

    rendered =
      try do
        Jido.AI.Accuracy.Helpers.eval_eex_quiet(template, assigns: assigns)
      rescue
        e -> {:error, {:template_error, Exception.message(e)}}
      end

    with {:ok, prompt_text} <- normalize_result(rendered),
         {:ok, feedback} <- call_llm(strategy, prompt_text, opts) do
      {:ok, cleanup_feedback(feedback)}
    end
  end

  @doc """
  Applies feedback to refine a response.

  ## Parameters

  - `strategy` - The SelfRefine strategy
  - `prompt` - The original question
  - `original_response` - The original response
  - `feedback` - The feedback to apply
  - `opts` - Additional options

  ## Returns

  `{:ok, refined_candidate}` or `{:error, reason}`

  """
  @spec apply_feedback(t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, Candidate.t()} | {:error, term()}
  def apply_feedback(%__MODULE__{} = strategy, prompt, original_response, feedback, opts \\ [])
      when is_binary(prompt) and is_binary(original_response) and is_binary(feedback) do
    template = strategy.refine_prompt || @default_refine_prompt

    assigns = [
      prompt: prompt,
      response: truncate_content(original_response),
      feedback: truncate_content(feedback)
    ]

    rendered =
      try do
        Jido.AI.Accuracy.Helpers.eval_eex_quiet(template, assigns: assigns)
      rescue
        e -> {:error, {:template_error, Exception.message(e)}}
      end

    with {:ok, prompt_text} <- normalize_result(rendered),
         {:ok, refined_content} <- call_llm(strategy, prompt_text, opts) do
      {:ok,
       Candidate.new!(%{
         id: "refined_#{Candidate.new!(%{}).id}",
         content: refined_content,
         model: strategy.model,
         timestamp: DateTime.utc_now(),
         metadata: %{
           self_refined: true,
           original_response_length: String.length(original_response)
         }
       })}
    end
  end

  @doc """
  Compares original and refined responses to measure improvement.

  ## Metrics

  - `:length_change` - Percentage change in length
  - `:length_delta` - Absolute character difference
  - `:original_length` - Character count of original
  - `:refined_length` - Character count of refined
  - `:improved` - Simple heuristic (longer = more detailed)

  ## Examples

      comparison = SelfRefine.compare_original_refined(original, refined)
      comparison.improved  # => true

  """
  @spec compare_original_refined(Candidate.t(), Candidate.t()) :: comparison()
  def compare_original_refined(%Candidate{} = original, %Candidate{} = refined) do
    original_len = content_length(original.content)
    refined_len = content_length(refined.content)

    length_delta = refined_len - original_len

    # Calculate percentage change
    length_change =
      if original_len > 0 do
        length_delta / original_len * 100
      else
        0.0
      end

    # Simple heuristic: refined response is "improved" if it's meaningfully longer
    # (at least 10% longer and at least 20 characters more)
    improved = length_change >= 10 and length_delta >= 20

    %{
      length_change: Float.round(length_change, 2),
      length_delta: length_delta,
      original_length: original_len,
      refined_length: refined_len,
      improved: improved
    }
  end

  # Private functions

  # credo:disable-for-next-line Credo.Check.Readability.VariableNames
  defp get_or_generate_original(%__MODULE{} = strategy, prompt, opts) do
    case Keyword.get(opts, :initial_candidate) do
      %Candidate{} = candidate ->
        {:ok, candidate}

      nil ->
        generate_original(strategy, prompt, opts)
    end
  end

  defp generate_original(%__MODULE__{} = strategy, prompt, opts) do
    with {:ok, content} <- call_llm(strategy, prompt, opts) do
      {:ok,
       Candidate.new!(%{
         content: content,
         model: strategy.model,
         timestamp: DateTime.utc_now(),
         metadata: %{self_refine_original: true}
       })}
    end
  end

  defp get_or_generate_feedback(%__MODULE__{} = strategy, prompt, %Candidate{} = original, opts) do
    case Keyword.get(opts, :feedback) do
      feedback when is_binary(feedback) ->
        {:ok, feedback}

      nil ->
        generate_feedback(strategy, prompt, original.content || "", opts)
    end
  end

  defp apply_refinement(%__MODULE__{} = strategy, prompt, %Candidate{} = original, feedback, opts) do
    apply_feedback(strategy, prompt, original.content || "", feedback, opts)
  end

  defp call_llm(%__MODULE__{} = strategy, prompt, opts) do
    model = Keyword.get(opts, :model, strategy.model)
    temperature = Keyword.get(opts, :temperature, strategy.temperature)
    timeout = Keyword.get(opts, :timeout, strategy.timeout)

    context =
      ReqLLM.Context.new()
      |> ReqLLM.Context.append(ReqLLM.Context.text(:user, prompt))

    reqllm_opts = [
      temperature: temperature,
      receive_timeout: timeout
    ]

    try do
      case ReqLLM.Generation.generate_text(model, context, reqllm_opts) do
        {:ok, response} ->
          content = extract_content(response)

          if content == "" do
            {:error, :no_content}
          else
            {:ok, String.trim(content)}
          end

        {:error, reason} ->
          {:error, {:llm_error, reason}}
      end
    rescue
      e ->
        {:error, {:llm_exception, Exception.message(e)}}
    end
  end

  defp extract_content(response) do
    Text.extract_text(response)
  end

  defp truncate_content(content) when is_binary(content) do
    max_length = 8_000

    if String.length(content) > max_length do
      String.slice(content, 0, max_length) <> "\n\n[Content truncated...]"
    else
      content
    end
  end

  defp cleanup_feedback(feedback) when is_binary(feedback) do
    feedback
    |> String.trim()
    |> String.replace(~r/^(Here is|Below is|The following is) your (feedback|review|analysis):/i, "")
    |> String.trim()
  end

  defp content_length(nil), do: 0
  defp content_length(content) when is_binary(content), do: String.length(content)

  defp normalize_result({:error, _} = error), do: error
  defp normalize_result(result), do: {:ok, result}

  # Validation

  defp validate_model(model) when is_binary(model) and model != "", do: :ok
  defp validate_model(_), do: {:error, :invalid_model}

  defp validate_temperature(temp) when is_number(temp) and temp >= 0.0 and temp <= 2.0, do: :ok
  defp validate_temperature(_), do: {:error, :invalid_temperature}

  defp validate_timeout(timeout) when is_integer(timeout) and timeout >= 1000 and timeout <= 300_000, do: :ok

  defp validate_timeout(_), do: {:error, :invalid_timeout}
  defp format_error(atom) when is_atom(atom), do: atom
end
