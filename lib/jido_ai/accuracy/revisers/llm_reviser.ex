defmodule Jido.AI.Accuracy.Revisers.LLMReviser do
  @moduledoc """
  LLM-based reviser that uses a language model to improve candidates based on critique.

  This reviser sends candidate responses along with critique feedback to an LLM
  and asks for an improved version that addresses the identified issues.

  ## Configuration

  - `:model` - Model to use for revision (default: from Config)
  - `:prompt_template` - Custom EEx template for revision prompt
  - `:preserve_correct` - Whether to preserve parts without issues (default: true)
  - `:temperature` - Temperature for LLM calls (default: 0.5)
  - `:timeout` - Timeout for LLM calls in ms (default: 30_000)
  - `:max_retries` - Maximum retry attempts (default: 2)
  - `:domain` - Optional domain for specialized revision

  ## Usage

      # Create reviser with defaults
      reviser = LLMReviser.new!(%{})

      # Revise a candidate based on critique
      {:ok, critique} = LLMCritiquer.critique(candidate, %{prompt: "What is 6 * 7?"})
      {:ok, revised} = LLMReviser.revise(reviser, candidate, critique, %{
        prompt: "What is 6 * 7?"
      })

      revised.content  # => Improved response addressing critique

  ## Revision Prompt Template

  The default prompt template uses EEx interpolation with these variables:
  - `@prompt` - The original question/prompt
  - `@candidate` - The candidate being revised
  - `@critique` - The critique feedback
  - `@preserve_correct` - Whether to preserve correct parts
  - `@domain` - Optional domain for specialized revision

  ## Change Tracking

  The reviser tracks what was changed:
  - Revision iteration number
  - Issues addressed
  - Suggestions incorporated
  - Previous version reference

  """

  @behaviour Jido.AI.Accuracy.Revision

  alias Jido.AI.Accuracy.{Candidate, Config, CritiqueResult}
  alias Jido.AI.Config, as: MainConfig

  @type t :: %__MODULE__{
          model: String.t(),
          prompt_template: String.t() | nil,
          preserve_correct: boolean(),
          temperature: number(),
          timeout: pos_integer(),
          max_retries: non_neg_integer(),
          domain: atom() | nil
        }

  defstruct [
    :model,
    prompt_template: nil,
    preserve_correct: true,
    temperature: 0.5,
    timeout: 30_000,
    max_retries: 2,
    domain: nil
  ]

  @default_prompt_template """
  You are an expert writer tasked with improving a response based on feedback.

  Original Question: <%= @prompt %>

  === ORIGINAL RESPONSE BEGINS ===
  <%= @candidate.content %>
  === ORIGINAL RESPONSE ENDS ===

  === FEEDBACK BEGINS ===
  Issues identified:
  <%= Enum.map(@critique.issues, fn i -> "- " <> i end) |> Enum.join("\\n") %>

  Suggestions for improvement:
  <%= Enum.map(@critique.suggestions, fn s -> "- " <> s end) |> Enum.join("\\n") %>

  Overall feedback: <%= @critique.feedback || "None provided" %>
  === FEEDBACK ENDS ===

  Please provide an improved response that addresses the feedback above.

  <%= if @preserve_correct do %>
  IMPORTANT: Only modify the parts that need improvement. Preserve any parts that are already correct.
  <% else %>
  You may rewrite the entire response if necessary.
  <% end %>

  Provide your response in the following format:

  ```json
  {
    "improved_response": "your improved response here",
    "changes_made": ["list of specific changes you made"],
    "parts_preserved": ["parts you kept unchanged"]
  }
  ```
  """

  @domain_guidelines %{
    math: "Focus on calculation accuracy and mathematical reasoning. Preserve correct steps, fix computational errors.",
    code: "Focus on syntax correctness, logic, and edge cases. Preserve working code, fix bugs and issues.",
    writing: "Focus on clarity, grammar, and coherence. Preserve good content, improve structure and style.",
    reasoning: "Focus on logical consistency and completeness. Preserve valid reasoning, fix gaps and errors."
  }

  @doc """
  Creates a new LLM reviser from the given attributes.

  ## Options

  - `:model` - Model to use (defaults to Config.default_model())
  - `:prompt_template` - Custom EEx template for revision
  - `:preserve_correct` - Whether to preserve correct parts (default: true)
  - `:temperature` - Temperature for LLM (default: 0.5)
  - `:timeout` - Timeout in ms (default: 30_000)
  - `:max_retries` - Max retry attempts (default: 2)
  - `:domain` - Optional domain atom for specialized revision

  ## Returns

  - `{:ok, reviser}` - Success
  - `{:error, reason}` - Validation failed

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) do
    model = Keyword.get(opts, :model, Config.default_model())

    # Resolve model alias if atom
    resolved_model =
      case model do
        atom when is_atom(atom) -> MainConfig.resolve_model(atom)
        binary when is_binary(binary) -> binary
      end

    # Validate
    with :ok <- validate_model(resolved_model),
         :ok <- validate_temperature(Keyword.get(opts, :temperature, 0.5)),
         :ok <- validate_timeout(Keyword.get(opts, :timeout, 30_000)) do
      reviser =
        struct(__MODULE__,
          model: resolved_model,
          prompt_template: Keyword.get(opts, :prompt_template),
          preserve_correct: Keyword.get(opts, :preserve_correct, true),
          temperature: Keyword.get(opts, :temperature, 0.5),
          timeout: Keyword.get(opts, :timeout, 30_000),
          max_retries: Keyword.get(opts, :max_retries, 2),
          domain: Keyword.get(opts, :domain)
        )

      {:ok, reviser}
    end
  end

  @doc """
  Creates a new LLM reviser, raising on error.

  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) do
    case new(opts) do
      {:ok, reviser} -> reviser
      {:error, reason} -> raise ArgumentError, "Invalid LLMReviser: #{format_error(reason)}"
    end
  end

  @impl true
  @doc """
  Revise a candidate using an LLM based on critique feedback.

  ## Context Options

  - `:prompt` - The original prompt/question
  - `:preserve_correct` - Override default preserve setting
  - `:revision_count` - Current iteration number (included in metadata)

  """
  @spec revise(t(), Candidate.t(), CritiqueResult.t(), map()) :: {:ok, Candidate.t()} | {:error, term()}
  def revise(%__MODULE__{} = reviser, %Candidate{} = candidate, %CritiqueResult{} = critique, context) do
    prompt = Map.get(context, :prompt, "")
    revision_count = Map.get(context, :revision_count, 0)

    with {:ok, rendered_prompt} <- render_prompt(reviser, candidate, critique, prompt),
         {:ok, response} <- call_llm(reviser, rendered_prompt),
         {:ok, parsed} <- parse_revision(response) do
      improved_content = Map.get(parsed, "improved_response", candidate.content)
      changes_made = Map.get(parsed, "changes_made", [])
      parts_preserved = Map.get(parsed, "parts_preserved", [])

      # Build revised candidate with metadata tracking changes
      revised_candidate =
        Candidate.new!(%{
          id: generate_revised_id(candidate.id, revision_count),
          content: improved_content,
          # Score would be re-evaluated
          score: nil,
          reasoning: candidate.reasoning,
          metadata:
            Map.merge(candidate.metadata || %{}, %{
              revision_of: candidate.id,
              revision_count: revision_count + 1,
              changes_made: changes_made,
              parts_preserved: parts_preserved,
              reviser: :llm,
              model: reviser.model,
              original_severity: critique.severity
            })
        })

      {:ok, revised_candidate}
    end
  end

  @impl true
  @doc """
  Generate a detailed diff showing what changed in the revision.

  """
  @spec diff(Candidate.t(), Candidate.t()) :: {:ok, map()}
  def diff(%Candidate{} = original, %Candidate{} = revised) do
    content_diff = compute_content_diff(original.content || "", revised.content || "")

    # Extract revision metadata
    revision_metadata = Map.get(revised.metadata || %{}, :changes_made, [])
    parts_preserved = Map.get(revised.metadata || %{}, :parts_preserved, [])

    {:ok,
     %{
       original_id: original.id,
       revised_id: revised.id,
       content_changed: content_diff != :unchanged,
       content_diff: content_diff,
       changes_made: revision_metadata,
       parts_preserved: parts_preserved,
       revision_count: Map.get(revised.metadata || %{}, :revision_count, 1),
       timestamp: System.system_time(:millisecond)
     }}
  end

  # Private functions

  defp render_prompt(%__MODULE__{} = reviser, candidate, critique, prompt) do
    template = reviser.prompt_template || @default_prompt_template

    # Build assigns for template
    assigns = [
      prompt: prompt,
      candidate: candidate,
      critique: critique,
      preserve_correct: reviser.preserve_correct,
      domain: reviser.domain,
      domain_guidelines: &domain_guidelines/1
    ]

    try do
      rendered = EEx.eval_string(template, assigns: assigns)
      {:ok, rendered}
    rescue
      e ->
        {:error, {:template_error, Exception.message(e)}}
    end
  end

  defp domain_guidelines(domain) when is_atom(domain) do
    Map.get(@domain_guidelines, domain, "")
  end

  defp call_llm(%__MODULE__{} = reviser, prompt) do
    model = reviser.model || Config.default_model()

    messages = [%ReqLLM.Message{role: :user, content: prompt}]

    reqllm_opts = [
      temperature: reviser.temperature,
      receive_timeout: reviser.timeout
    ]

    try do
      case ReqLLM.Generation.generate_text(model, messages, reqllm_opts) do
        {:ok, response} ->
          content = extract_content(response)

          if content != "" do
            {:ok, content}
          else
            {:error, :no_content}
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
    case response.message.content do
      nil ->
        ""

      content when is_binary(content) ->
        content

      content when is_list(content) ->
        content
        |> Enum.filter(fn %{type: type} -> type == :text end)
        |> Enum.map_join("", fn %{text: text} -> text end)
    end
  end

  defp parse_revision(response) when is_binary(response) do
    # Try to extract JSON from the response
    json_str = extract_json(response)

    case Jason.decode(json_str) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, parsed}

      {:error, _} ->
        # Fallback: treat entire response as improved content
        {:ok,
         %{
           "improved_response" => response,
           "changes_made" => ["Full revision"],
           "parts_preserved" => []
         }}
    end
  end

  defp extract_json(response) do
    # Look for JSON code blocks
    json_block_regex = ~r/```json\s*(\{.*?\})\s*```/s
    code_block_regex = ~r/```\s*(\{.*?\})\s*```/s
    plain_json_regex = ~r/(\{[^{}]*"improved_response"[^{}]*\})/s

    cond do
      Regex.run(json_block_regex, response) != nil ->
        case Regex.run(json_block_regex, response, capture: :all) do
          [[_, match]] -> match
          _ -> response
        end

      Regex.run(code_block_regex, response) != nil ->
        case Regex.run(code_block_regex, response, capture: :all) do
          [[_, match]] -> match
          _ -> response
        end

      Regex.run(plain_json_regex, response) != nil ->
        case Regex.run(plain_json_regex, response, capture: :all) do
          [[_, match]] -> match
          _ -> response
        end

      true ->
        response
    end
  end

  @dialyzer {:nowarn_function, extract_json: 1}

  defp compute_content_diff("", ""), do: :unchanged
  defp compute_content_diff(original, original), do: :unchanged

  defp compute_content_diff(original, revised) do
    # Simple line-by-line diff
    original_lines = String.split(original, "\n")
    revised_lines = String.split(revised, "\n")

    changed_lines =
      original_lines
      |> Enum.zip(revised_lines)
      |> Enum.with_index()
      |> Enum.filter(fn {pair, _i} ->
        {o, r} = pair
        o != r
      end)
      |> Enum.map(fn {pair, i} ->
        {_o, r} = pair
        {i, r}
      end)

    %{
      type: :line_diff,
      original_length: length(original_lines),
      revised_length: length(revised_lines),
      changed_lines: changed_lines,
      changes_count: length(changed_lines)
    }
  end

  defp generate_revised_id(original_id, revision_count) do
    "#{original_id}-rev#{revision_count + 1}"
  end

  # Validation

  defp validate_model(model) when is_binary(model) and model != "", do: :ok
  defp validate_model(_), do: {:error, :invalid_model}

  defp validate_temperature(temp) when is_number(temp) and temp >= 0.0 and temp <= 2.0, do: :ok
  defp validate_temperature(_), do: {:error, :invalid_temperature}

  defp validate_timeout(timeout) when is_integer(timeout) and timeout >= 1000 and timeout <= 300_000, do: :ok

  defp validate_timeout(_), do: {:error, :invalid_timeout}
  defp format_error(atom) when is_atom(atom), do: atom
end
