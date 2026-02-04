defmodule Mix.Tasks.JidoAi.Accuracy do
  @shortdoc "Improve LLM accuracy via self-consistency or multi-stage pipeline"

  @moduledoc """
  Improve LLM response accuracy using test-time compute scaling techniques.

  This task provides two modes for improving accuracy:

  1. **Self-Consistency** (default) - Generate multiple candidates, select best via voting
  2. **Pipeline** - Full multi-stage pipeline with difficulty estimation, verification, etc.

  ## Quick Start

      # Simple self-consistency (generates 5 candidates, picks majority)
      mix jido_ai.accuracy "What is 15 * 23?"

      # Full pipeline with balanced preset
      mix jido_ai.accuracy "What is 15 * 23?" --preset balanced

  ## Self-Consistency Mode (Default)

  Generates N candidate responses with varied temperatures and selects the most
  common answer via majority voting. This simple technique significantly improves
  accuracy on reasoning tasks.

      # More candidates = higher accuracy (but more cost)
      mix jido_ai.accuracy "What is 15 * 23?" --candidates 10

      # Chain-of-Thought reasoning
      mix jido_ai.accuracy "Solve step by step: 15 * 23 + 7" --reasoning

      # Different aggregation strategy
      mix jido_ai.accuracy "Question" --aggregator best_of_n

  ## Pipeline Mode

  Use `--preset` to run the full accuracy pipeline with multiple stages:

      mix jido_ai.accuracy "Complex question" --preset accurate

  ### Available Presets

      ┌─────────────┬────────────────────────────────────┬─────────────────────┐
      │ Preset      │ Stages                             │ Use Case            │
      ├─────────────┼────────────────────────────────────┼─────────────────────┤
      │ fast        │ generation → calibration           │ Quick answers       │
      │ balanced    │ + difficulty → verification        │ General use         │
      │ accurate    │ + search → reflection              │ Maximum accuracy    │
      │ coding      │ + RAG + code verifiers             │ Code correctness    │
      │ research    │ + RAG + factuality                 │ Factual QA          │
      └─────────────┴────────────────────────────────────┴─────────────────────┘

  ## Options

  ### Common
      --model MODEL        LLM model (default: anthropic:claude-haiku-4-5)
      --timeout MS         Timeout in milliseconds
      --verbose            Show detailed output and metadata

  ### Self-Consistency Mode
      --candidates N       Number of candidates to generate (default: 5)
      --aggregator STRAT   majority_vote | best_of_n | weighted
      --reasoning          Enable Chain-of-Thought reasoning
      --temperature T      Fixed temperature (default: randomized 0.0-1.0)
      --concurrency N      Max parallel generations (default: 3)
      --system-prompt TXT  System prompt for all generations

  ### Pipeline Mode
      --preset NAME        fast | balanced | accurate | coding | research

  ## Examples

      # High-confidence math answer
      mix jido_ai.accuracy "What is 847 * 29?" --candidates 7

      # Code question with coding preset
      mix jido_ai.accuracy "How to reverse a list in Elixir?" --preset coding

      # Maximum accuracy with trace
      mix jido_ai.accuracy "Explain relativity" --preset accurate --verbose

      # Fast model, more candidates
      mix jido_ai.accuracy "Capital of France?" --model openai:gpt-4o-mini --candidates 10

  ## See Also

  - `mix help jido_ai.gepa` - Prompt template evaluation
  - `Jido.AI.improve_accuracy/2` - Programmatic API
  - `Jido.AI.run_pipeline/2` - Pipeline API
  """

  use Mix.Task

  alias Jido.AI.Accuracy.{Pipeline, Presets, SelfConsistency}

  @switches [
    model: :string,
    candidates: :integer,
    aggregator: :string,
    reasoning: :boolean,
    temperature: :float,
    timeout: :integer,
    concurrency: :integer,
    system_prompt: :string,
    preset: :string,
    verbose: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.rerun("app.start")
    load_dotenv()

    {opts, rest, _} = OptionParser.parse(args, strict: @switches)

    prompt = Enum.join(rest, " ")

    if prompt == "" do
      raise "Usage: mix jido_ai.accuracy \"your prompt here\" [options]"
    end

    if opts[:preset] do
      run_pipeline(prompt, opts)
    else
      run_self_consistency(prompt, opts)
    end
  end

  # ============================================================================
  # Self-Consistency Mode
  # ============================================================================

  defp run_self_consistency(prompt, opts) do
    params = self_consistency_params(opts)

    print_self_consistency_header(prompt, params)

    sc_opts = build_self_consistency_opts(params, opts)

    IO.write("Generating #{params.num_candidates} candidates... ")

    {result, duration} =
      time_ms(fn ->
        run_self_consistency_request(prompt, sc_opts, params.use_reasoning)
      end)

    handle_self_consistency_result(result, duration, params.use_reasoning, params.verbose)
  end

  # ============================================================================
  # Pipeline Mode
  # ============================================================================

  defp run_pipeline(prompt, opts) do
    params = pipeline_params(opts)

    print_pipeline_header(prompt, params)

    case Presets.get(params.preset) do
      {:ok, config} ->
        run_pipeline_with_config(prompt, config, params)

      {:error, :unknown_preset} ->
        print_unknown_preset(opts[:preset])
    end
  end

  defp self_consistency_params(opts) do
    %{
      model: opts[:model] || "anthropic:claude-haiku-4-5",
      num_candidates: opts[:candidates] || 5,
      aggregator: parse_aggregator(opts[:aggregator] || "majority_vote"),
      use_reasoning: opts[:reasoning] || false,
      timeout: opts[:timeout] || 30_000,
      max_concurrency: opts[:concurrency] || 3,
      verbose: opts[:verbose] || false
    }
  end

  defp print_self_consistency_header(prompt, params) do
    IO.puts("\n=== Jido AI Accuracy (Self-Consistency) ===\n")
    IO.puts("Prompt: #{prompt}")
    IO.puts("Model: #{params.model}")
    IO.puts("Candidates: #{params.num_candidates}")
    IO.puts("Aggregator: #{params.aggregator}")

    if params.use_reasoning do
      IO.puts("Mode: Chain-of-Thought")
    end

    IO.puts("")
  end

  defp build_self_consistency_opts(params, opts) do
    [
      model: params.model,
      num_candidates: params.num_candidates,
      aggregator: params.aggregator,
      timeout: params.timeout,
      max_concurrency: params.max_concurrency
    ]
    |> maybe_add_temperature(opts[:temperature])
    |> maybe_add_system_prompt(opts[:system_prompt])
  end

  defp run_self_consistency_request(prompt, sc_opts, true) do
    SelfConsistency.run_with_reasoning(prompt, sc_opts)
  end

  defp run_self_consistency_request(prompt, sc_opts, false) do
    SelfConsistency.run(prompt, sc_opts)
  end

  defp handle_self_consistency_result({:ok, best, metadata}, duration, use_reasoning, verbose) do
    IO.puts("done (#{duration}ms)\n")
    print_self_consistency_result(best, metadata, use_reasoning, verbose)
  end

  defp handle_self_consistency_result({:error, reason}, _duration, _use_reasoning, _verbose) do
    IO.puts("failed\n")
    IO.puts("Error: #{inspect(reason)}")
  end

  defp pipeline_params(opts) do
    %{
      preset: parse_preset(opts[:preset]),
      model: opts[:model] || "anthropic:claude-haiku-4-5",
      timeout: opts[:timeout] || 60_000,
      verbose: opts[:verbose] || false
    }
  end

  defp print_pipeline_header(prompt, params) do
    IO.puts("\n=== Jido AI Accuracy (Pipeline) ===\n")
    IO.puts("Prompt: #{prompt}")
    IO.puts("Model: #{params.model}")
    IO.puts("Preset: #{params.preset}")
  end

  defp run_pipeline_with_config(prompt, config, params) do
    IO.puts("Stages: #{inspect(config.stages)}")
    IO.puts("")

    generator = build_generator(params.model)

    IO.write("Running pipeline... ")

    {result, duration} =
      time_ms(fn ->
        run_pipeline_execution(config, prompt, generator, params.timeout)
      end)

    handle_pipeline_execution_result(result, duration, params.verbose)
  end

  defp run_pipeline_execution(config, prompt, generator, timeout) do
    case Pipeline.new(%{config: config}) do
      {:ok, pipeline} ->
        Pipeline.run(pipeline, prompt, generator: generator, timeout: timeout)

      {:error, reason} ->
        {:error, {:pipeline_creation, reason}}
    end
  end

  defp handle_pipeline_execution_result({:ok, pipeline_result}, duration, verbose) do
    IO.puts("done (#{duration}ms)\n")
    print_pipeline_result(pipeline_result, verbose)
  end

  defp handle_pipeline_execution_result({:error, {:pipeline_creation, reason}}, _duration, _verbose) do
    IO.puts("failed\n")
    IO.puts("Pipeline creation error: #{inspect(reason)}")
  end

  defp handle_pipeline_execution_result({:error, reason}, _duration, _verbose) do
    IO.puts("failed\n")
    IO.puts("Error: #{inspect(reason)}")
  end

  defp print_unknown_preset(preset) do
    IO.puts("\nError: Unknown preset '#{preset}'")
    IO.puts("Available presets: #{inspect(Presets.list())}")
  end

  defp time_ms(fun) when is_function(fun, 0) do
    start_time = System.monotonic_time(:millisecond)
    result = fun.()
    duration = System.monotonic_time(:millisecond) - start_time
    {result, duration}
  end

  defp build_generator(model) do
    fn query, _context ->
      messages = [%{role: "user", content: query}]

      case ReqLLM.Generation.generate_text(model, messages, []) do
        {:ok, response} ->
          content = extract_output(response)
          {:ok, content}

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

  defp extract_output(_), do: ""

  # ============================================================================
  # Helpers
  # ============================================================================

  defp parse_aggregator("majority_vote"), do: :majority_vote
  defp parse_aggregator("best_of_n"), do: :best_of_n
  defp parse_aggregator("weighted"), do: :weighted
  defp parse_aggregator(other), do: String.to_atom(other)

  defp parse_preset(preset) when is_binary(preset), do: String.to_atom(preset)
  defp parse_preset(preset), do: preset

  defp maybe_add_temperature(opts, nil), do: opts

  defp maybe_add_temperature(opts, temp) do
    Keyword.put(opts, :temperature_range, {temp, temp})
  end

  defp maybe_add_system_prompt(opts, nil), do: opts

  defp maybe_add_system_prompt(opts, prompt) do
    Keyword.put(opts, :system_prompt, prompt)
  end

  # ============================================================================
  # Output Formatting
  # ============================================================================

  defp print_self_consistency_result(best, metadata, use_reasoning, verbose) do
    IO.puts("=== Best Answer ===\n")

    reasoning = get_field(best, :reasoning)
    content = get_field(best, :content)

    if (use_reasoning and reasoning) && reasoning != "" do
      IO.puts("Reasoning:")
      IO.puts(reasoning)
      IO.puts("\nAnswer:")
      IO.puts(content)
    else
      IO.puts(content)
    end

    IO.puts("\n=== Metrics ===\n")
    IO.puts("Confidence:  #{Float.round(metadata.confidence * 100, 1)}%")
    IO.puts("Candidates:  #{metadata.num_candidates}")

    if metadata.total_tokens do
      IO.puts("Tokens:      #{metadata.total_tokens}")
    end

    if verbose do
      print_aggregation_details(metadata)
    end
  end

  defp print_pipeline_result(result, verbose) do
    IO.puts("=== Result ===\n")

    if result.answer do
      IO.puts(result.answer)
    else
      IO.puts("(No answer - action: #{result.action})")
    end

    IO.puts("\n=== Metrics ===\n")
    IO.puts("Confidence:  #{Float.round(result.confidence * 100, 1)}%")
    IO.puts("Action:      #{result.action}")

    metadata = result.metadata

    if metadata[:total_duration_ms] do
      IO.puts("Duration:    #{metadata[:total_duration_ms]}ms")
    end

    if metadata[:num_candidates] && metadata[:num_candidates] > 0 do
      IO.puts("Candidates:  #{metadata[:num_candidates]}")
    end

    if metadata[:difficulty] do
      IO.puts("Difficulty:  #{metadata[:difficulty]}")
    end

    if verbose do
      print_pipeline_trace(result)
    end
  end

  defp print_pipeline_trace(result) do
    IO.puts("\n=== Pipeline Trace ===\n")

    Enum.each(result.trace, fn entry ->
      status = if entry.status == :ok, do: "✓", else: "✗"
      IO.puts("#{status} #{entry.stage} (#{entry.duration_ms}ms)")

      if entry.status == :error do
        IO.puts("  Error: #{inspect(entry.metadata)}")
      end
    end)
  end

  defp print_aggregation_details(metadata) do
    IO.puts("\n=== Aggregation Details ===\n")

    agg_meta = metadata.aggregation_metadata

    case agg_meta do
      %{vote_counts: counts} when is_map(counts) ->
        IO.puts("Vote distribution:")

        counts
        |> Enum.sort_by(fn {_k, v} -> -v end)
        |> Enum.each(fn {answer, count} ->
          preview = String.slice(to_string(answer), 0, 50)
          IO.puts("  #{count} votes: #{preview}")
        end)

      %{candidates: candidates} when is_list(candidates) ->
        IO.puts("Candidate scores:")

        candidates
        |> Enum.with_index(1)
        |> Enum.each(fn {candidate, i} ->
          score = Map.get(candidate, :score, "N/A")
          content = Map.get(candidate, :content, "")
          preview = String.slice(content, 0, 50)
          IO.puts("  #{i}. (score: #{score}) #{preview}")
        end)

      _ ->
        IO.puts("Raw metadata: #{inspect(agg_meta, pretty: true)}")
    end
  end

  defp get_field(%{__struct__: _} = struct, field), do: Map.get(struct, field)

  defp load_dotenv do
    if Code.ensure_loaded?(Dotenvy) do
      env_file = Path.join(File.cwd!(), ".env")

      if File.exists?(env_file) do
        Dotenvy.source!([env_file])
      end
    end
  end
end
