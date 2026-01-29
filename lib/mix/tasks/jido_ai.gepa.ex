defmodule Mix.Tasks.JidoAi.Gepa do
  @shortdoc "Evaluate a prompt template using GEPA metrics"

  @moduledoc """
  #{@shortdoc}

  ## Usage

      # Evaluate a simple prompt template
      mix jido_ai.gepa --template "Answer concisely: {{input}}"

      # With a specific model
      mix jido_ai.gepa --template "{{input}}" --model openai:gpt-4o-mini

      # Add a mutation candidate to compare
      mix jido_ai.gepa --template "{{input}}" --mutate

      # Custom tasks from JSON file
      mix jido_ai.gepa --template "{{input}}" --tasks tasks.json

      # Verbose output showing per-task results
      mix jido_ai.gepa --template "{{input}}" --verbose

  ## Options

  - `--template` - The prompt template (must include {{input}})
  - `--model` - LLM model (default: openai:gpt-4o-mini)
  - `--mutate` - Add a "be concise" mutation candidate for comparison
  - `--tasks` - JSON file with tasks (format: [{"input": "...", "expected": "..."}])
  - `--timeout` - Timeout per task in ms (default: 30000)
  - `--verbose` - Show per-task results

  ## Tasks JSON Format

      [
        {"input": "What is 2+2?", "expected": "4"},
        {"input": "What is 3+3?", "expected": "6"}
      ]

  ## Output

  Shows accuracy, token cost, and latency for each variant, then picks the best.
  """

  use Mix.Task

  alias Jido.AI.GEPA.Task, as: GEPATask
  alias Jido.AI.GEPA.{Evaluator, PromptVariant}

  @switches [
    template: :string,
    model: :string,
    mutate: :boolean,
    tasks: :string,
    timeout: :integer,
    verbose: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    load_dotenv()

    {opts, _rest, _} = OptionParser.parse(args, strict: @switches)

    template = opts[:template] || Mix.raise("--template is required")
    model = opts[:model] || "openai:gpt-4o-mini"
    timeout = opts[:timeout] || 30_000
    verbose = opts[:verbose] || false

    tasks = load_tasks(opts[:tasks])
    variants = build_variants(template, opts[:mutate])

    IO.puts("\n=== GEPA Prompt Evaluation ===\n")
    IO.puts("Model: #{model}")
    IO.puts("Tasks: #{length(tasks)}")
    IO.puts("Variants: #{length(variants)}\n")

    eval_opts = [
      runner: runner_fn(model),
      timeout: timeout,
      runner_opts: [model: model]
    ]

    results =
      Enum.map(variants, fn variant ->
        IO.write("Evaluating: #{preview(variant.template)}... ")

        case Evaluator.evaluate_variant(variant, tasks, eval_opts) do
          {:ok, result} ->
            IO.puts("done (accuracy: #{Float.round(result.accuracy * 100, 1)}%)")
            {variant, result}

          {:error, reason} ->
            IO.puts("error: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(results) do
      Mix.raise("All evaluations failed")
    end

    print_summary(results)
    {best_variant, best_result} = pick_best(results)

    IO.puts("\n=== Best Variant ===\n")
    IO.puts(best_variant.template)
    IO.puts("\nMetrics:")
    IO.puts("  Accuracy:   #{Float.round(best_result.accuracy * 100, 1)}%")
    IO.puts("  Tokens:     #{best_result.token_cost}")
    IO.puts("  Avg Latency: #{best_result.latency_ms}ms")

    if verbose do
      print_detailed_results(best_result)
    end
  end

  defp runner_fn(model) do
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

  defp extract_output(%{"choices" => [%{"message" => %{"content" => content}} | _]}), do: content
  defp extract_output(response) when is_binary(response), do: response
  defp extract_output(_), do: ""

  defp extract_tokens(%ReqLLM.Response{usage: %{total_tokens: tokens}}), do: tokens
  defp extract_tokens(%{"usage" => %{"total_tokens" => tokens}}), do: tokens
  defp extract_tokens(_), do: 0

  defp build_variants(template, mutate?) do
    base = [PromptVariant.new!(%{template: template})]

    if mutate? do
      mutation =
        template <>
          "\n\nRules:\n- Answer with ONLY the final answer.\n- No explanations or extra text."

      base ++ [PromptVariant.new!(%{template: mutation})]
    else
      base
    end
  end

  defp load_tasks(nil), do: default_tasks()

  defp load_tasks(path) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> Enum.map(fn %{"input" => input, "expected" => expected} ->
      GEPATask.new!(%{input: input, expected: expected})
    end)
  end

  defp default_tasks do
    [
      GEPATask.new!(%{input: "What is 2+2?", expected: "4"}),
      GEPATask.new!(%{input: "What is 3+3?", expected: "6"}),
      GEPATask.new!(%{input: "What is 10-5?", expected: "5"}),
      GEPATask.new!(%{input: "Return the word YES", expected: "YES"})
    ]
  end

  defp pick_best(results) do
    Enum.max_by(results, fn {_variant, res} ->
      {res.accuracy, -res.token_cost, -res.latency_ms}
    end)
  end

  defp print_summary(results) do
    IO.puts("\n--- Results ---")
    IO.puts("Accuracy\tTokens\tLatency\tTemplate")

    Enum.each(results, fn {variant, res} ->
      IO.puts(
        "#{Float.round(res.accuracy * 100, 1)}%\t\t#{res.token_cost}\t#{res.latency_ms}ms\t#{preview(variant.template)}"
      )
    end)
  end

  defp print_detailed_results(result) do
    IO.puts("\n--- Per-Task Results ---")

    Enum.each(result.results, fn r ->
      status = if r.success, do: "✓", else: "✗"
      IO.puts("#{status} #{r.task.input}")
      IO.puts("  Expected: #{r.task.expected || "any"}")
      IO.puts("  Got: #{r.output || "(error: #{inspect(r.error)})"}")
      IO.puts("  Tokens: #{r.tokens}, Latency: #{r.latency_ms}ms")
    end)
  end

  defp preview(template) do
    template
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 50)
    |> then(&if(String.length(template) > 50, do: &1 <> "...", else: &1))
  end

  defp load_dotenv do
    if Code.ensure_loaded?(Dotenvy) do
      env_file = Path.join(File.cwd!(), ".env")

      if File.exists?(env_file) do
        Dotenvy.source!([env_file])
      end
    end
  end
end
