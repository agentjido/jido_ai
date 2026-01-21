defmodule Jido.AI.Accuracy.Generators.LLMGenerator do
  @moduledoc """
  LLM-based candidate generator for the accuracy improvement system.

  This generator produces multiple candidate responses by sampling from
  a language model with varied temperature parameters. Supports parallel
  generation for efficiency and Chain-of-Thought prompts.

  ## Configuration

  - `:model` - Model to use (default: `"anthropic:claude-haiku-4-5"`)
  - `:num_candidates` - Number of candidates to generate (default: 5)
  - `:temperature_range` - Range for temperature variation (default: `{0.0, 1.0}`)
  - `:timeout` - Per-candidate timeout in ms (default: 30000)
  - `:max_concurrency` - Max parallel generations (default: 3)
  - `:system_prompt` - Optional system prompt

  ## Usage

      # Create generator with config
      generator = LLMGenerator.new!(%{
        model: :fast,
        num_candidates: 5,
        temperature_range: {0.5, 1.0}
      })

      # Generate candidates
      {:ok, candidates} = LLMGenerator.generate_candidates(generator, "What is 2+2?")

      # Generate with Chain-of-Thought
      {:ok, candidates} = LLMGenerator.generate_with_reasoning(
        generator,
        "Solve step by step: 15 * 23 + 7"
      )
  """

  @behaviour Jido.AI.Accuracy.Generator

  alias Jido.AI.Accuracy.{Candidate, Generator, Config}
  alias Jido.AI.Config, as: MainConfig

  @type t :: %__MODULE__{
          model: String.t(),
          num_candidates: pos_integer(),
          temperature_range: {number(), number()},
          timeout: pos_integer(),
          max_concurrency: pos_integer(),
          system_prompt: String.t() | nil
        }

  defstruct [
    :model,
    :num_candidates,
    :temperature_range,
    :timeout,
    :max_concurrency,
    system_prompt: nil
  ]

  # Use centralized Config module for defaults and bounds
  # Security bounds - prevent DoS through resource exhaustion
  # These module attributes are needed for guard expressions (Config functions cannot be used in guards)
  @max_num_candidates Config.max_num_candidates()
  @min_num_candidates Config.min_num_candidates()
  @max_concurrency_limit Config.max_concurrency_limit()
  @min_concurrency Config.min_concurrency()
  @max_timeout Config.max_timeout()
  @min_timeout Config.min_timeout()

  @doc """
  Creates a new LLMGenerator with the given configuration.

  ## Options

  - `:model` - Model spec or alias (default: from Config)
  - `:num_candidates` - Number of candidates (default: from Config, max: 100)
  - `:temperature_range` - Temperature range `{min, max}` (default: `{0.0, 1.0}`)
  - `:timeout` - Timeout in ms (default: from Config, range: 1000-300000)
  - `:max_concurrency` - Max parallel requests (default: from Config, max: 50)
  - `:system_prompt` - Optional system prompt

  ## Examples

      LLMGenerator.new!(%{
        model: :fast,
        num_candidates: 3,
        temperature_range: {0.5, 1.0}
      })
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

    temperature_range = Keyword.get(opts, :temperature_range, Config.default_temperature_range())
    num_candidates = Keyword.get(opts, :num_candidates, Config.default_num_candidates())
    timeout = Keyword.get(opts, :timeout, Config.default_timeout())
    max_concurrency = Keyword.get(opts, :max_concurrency, Config.default_max_concurrency())

    # Validate all parameters with security bounds
    with :ok <- validate_temperature_range(temperature_range),
         :ok <- validate_num_candidates(num_candidates),
         :ok <- validate_timeout(timeout),
         :ok <- validate_max_concurrency(max_concurrency) do
      {:ok,
       %__MODULE__{
         model: resolved_model,
         num_candidates: num_candidates,
         temperature_range: temperature_range,
         timeout: timeout,
         max_concurrency: max_concurrency,
         system_prompt: Keyword.get(opts, :system_prompt)
       }}
    end
  end

  @doc """
  Creates a new LLMGenerator, raising on error.
  """
  @spec new!(keyword()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, generator} -> generator
      {:error, reason} -> raise ArgumentError, "Invalid LLMGenerator: #{format_error(reason)}"
    end
  end

  @doc """
  Generates multiple candidates from a prompt.

  Candidates are generated in parallel with randomized temperatures
  within the configured range for diversity.

  ## Options

  Overrides generator configuration:
  - `:num_candidates` - Number of candidates
  - `:temperature` - Fixed temperature (overrides randomization)
  - `:temperature_range` - Temperature range for randomization
  - `:timeout` - Per-candidate timeout
  - `:max_concurrency` - Max parallel generations

  ## Examples

      {:ok, candidates} = LLMGenerator.generate_candidates(generator, "What is 2+2?")
  """
  @impl Generator
  @spec generate_candidates(t(), String.t(), keyword()) :: Generator.generate_result()
  def generate_candidates(%__MODULE__{} = generator, prompt, opts \\ []) do
    num_candidates = Keyword.get(opts, :num_candidates, generator.num_candidates)
    temperature_range = Keyword.get(opts, :temperature_range, generator.temperature_range)
    timeout = Keyword.get(opts, :timeout, generator.timeout)
    max_concurrency = Keyword.get(opts, :max_concurrency, generator.max_concurrency)
    fixed_temperature = Keyword.get(opts, :temperature)

    # Prepare generator tasks
    tasks =
      Enum.map(1..num_candidates, fn _i ->
        temp =
          if fixed_temperature == nil do
            random_temperature(temperature_range)
          else
            fixed_temperature
          end

        {prompt, temp}
      end)

    # Generate in parallel
    results =
      tasks
      |> Task.async_stream(
        fn {p, temp} -> generate_one(generator, p, temp, timeout, opts) end,
        max_concurrency: max_concurrency,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, {:ok, candidate}} -> candidate
        {:ok, {:error, _reason}} -> nil
        {:exit, _reason} -> nil
      end)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(results) do
      {:error, :all_generations_failed}
    else
      {:ok, results}
    end
  end

  @doc """
  Generates candidates asynchronously.

  Returns a Task that resolves to the same result as `generate_candidates/3`.

  ## Examples

      task = LLMGenerator.generate_candidates_async(generator, "What is 2+2?")
      {:ok, candidates} = Task.await(task)
  """
  @impl Generator
  @spec generate_candidates_async(t(), String.t(), keyword()) :: Task.t()
  def generate_candidates_async(%__MODULE__{} = generator, prompt, opts \\ []) do
    Task.async(fn -> generate_candidates(generator, prompt, opts) end)
  end

  @doc """
  Generates candidates with Chain-of-Thought reasoning.

  Prompts the model to think step-by-step and stores the reasoning trace
  separately from the final answer in the candidate's `:reasoning` field.

  ## Examples

      {:ok, candidates} = LLMGenerator.generate_with_reasoning(
        generator,
        "Solve: 15 * 23 + 7"
      )

      iex> List.first(candidates).reasoning
      "Let me calculate step by step..."

      iex> List.first(candidates).content
      "The answer is 352"
  """
  @impl Generator
  @spec generate_with_reasoning(t(), String.t(), keyword()) :: Generator.generate_result()
  def generate_with_reasoning(%__MODULE__{} = generator, prompt, opts \\ []) do
    # Add CoT prefix to prompt
    cot_prompt =
      "Think step by step to solve this problem. Show your reasoning clearly, then provide the final answer.\n\n" <>
        prompt

    # Generate candidates
    case generate_candidates(generator, cot_prompt, opts) do
      {:ok, candidates} ->
        # Parse reasoning and content from each candidate
        parsed_candidates =
          Enum.map(candidates, fn candidate ->
            parse_reasoning_content(candidate.content)
          end)

        {:ok, parsed_candidates}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp generate_one(%__MODULE__{} = generator, prompt, temperature, timeout, _opts) do
    messages = build_messages(generator.system_prompt, prompt)

    reqllm_opts =
      [
        temperature: temperature,
        receive_timeout: timeout
      ]
      |> add_model_opt(generator.model)

    case ReqLLM.Generation.generate_text(generator.model, messages, reqllm_opts) do
      {:ok, response} ->
        content = extract_content(response)
        tokens = count_tokens(response)

        candidate_opts =
          []
          |> Keyword.put(:content, content)
          |> Keyword.put(:tokens_used, tokens)
          |> Keyword.put(:model, generator.model)
          |> Keyword.put(:metadata, %{temperature: temperature})

        Candidate.new(candidate_opts)

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e in [ArgumentError, KeyError, MatchError, RuntimeError] ->
      {:error, {:exception, Exception.message(e), struct: e.__struct__}}
  end

  defp build_messages(nil, prompt) do
    [%ReqLLM.Message{role: :user, content: prompt}]
  end

  defp build_messages(system_prompt, prompt) do
    [
      %ReqLLM.Message{role: :system, content: system_prompt},
      %ReqLLM.Message{role: :user, content: prompt}
    ]
  end

  defp extract_content(response) do
    case response.message.content do
      nil ->
        ""

      content when is_binary(content) ->
        content

      content when is_list(content) ->
        content
        |> Enum.filter(fn
          %{type: :text} -> true
          _ -> false
        end)
        |> Enum.map_join("", fn %{text: text} -> text end)
    end
  end

  defp count_tokens(response) do
    case response.usage do
      nil ->
        0

      usage ->
        input_tokens = Map.get(usage, :input_tokens, 0)
        output_tokens = Map.get(usage, :output_tokens, 0)
        input_tokens + output_tokens
    end
  end

  defp random_temperature({min_temp, max_temp}) do
    :rand.uniform() * (max_temp - min_temp) + min_temp
  end

  # Validation functions with security bounds (module attributes for guard compatibility)

  defp validate_temperature_range({min, max})
       when is_number(min) and is_number(max) and min >= 0 and max <= 2 and min <= max, do: :ok

  defp validate_temperature_range(_), do: {:error, :invalid_temperature_range}

  defp validate_num_candidates(n) when is_integer(n) and n >= @min_num_candidates and n <= @max_num_candidates, do: :ok

  defp validate_num_candidates(_), do: {:error, :invalid_num_candidates}

  defp validate_timeout(t) when is_integer(t) and t >= @min_timeout and t <= @max_timeout, do: :ok

  defp validate_timeout(_), do: {:error, :invalid_timeout}

  defp validate_max_concurrency(n) when is_integer(n) and n >= @min_concurrency and n <= @max_concurrency_limit, do: :ok

  defp validate_max_concurrency(_), do: {:error, :invalid_max_concurrency}

  defp add_model_opt(opts, _model) do
    # ReqLLM handles model in the first argument, so no need to add to opts
    opts
  end

  # Chain-of-Thought reasoning parsing
  defp parse_reasoning_content(content) do
    # Try to split on common final answer patterns
    # Each pattern has: {marker, pattern_with_newlines}
    # We search for the marker, then split around it
    patterns = [
      {"Final answer:", "\n\nFinal answer:"},
      {"Therefore:", "\n\nTherefore:"},
      {"Thus:", "\n\nThus:"},
      {"So:", "\n\nSo:"},
      {"The answer is:", "\n\nThe answer is:"},
      {"Result:", "\n\nResult:"}
    ]

    case find_reasoning_split(content, patterns) do
      {reasoning, answer} ->
        %{reasoning: String.trim(reasoning), content: String.trim(answer)}

      nil ->
        %{reasoning: "", content: content}
    end
  end

  defp find_reasoning_split(content, [{_marker, pattern} | rest]) do
    case String.split(content, pattern, parts: 2) do
      [reasoning, answer] -> {reasoning, answer}
      [_single_part] -> find_reasoning_split(content, rest)
    end
  end

  defp find_reasoning_split(_, []), do: nil
  defp format_error(atom) when is_atom(atom), do: atom
  defp format_error(_), do: :invalid_attributes
end
