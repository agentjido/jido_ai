defmodule Mix.Tasks.Jido.Ai.StreamText do
  @shortdoc "Stream text generation from AI models"

  @moduledoc """
  Mix task for streaming text generation from AI models.

  Provides real-time streaming text generation with cost tracking and usage metrics.
  """
  use Mix.Task

  alias Jido.AI.{CostCalculator, Model, TokenCounter}

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:jido_ai)

    {opts, args_list, _} =
      OptionParser.parse(args,
        switches: [
          model: :string,
          system: :string,
          max_tokens: :integer,
          temperature: :float,
          verbose: :boolean,
          metrics: :boolean,
          quiet: :boolean
        ]
      )

    prompt =
      case args_list do
        [p | _] ->
          p

        [] ->
          IO.puts("Usage: mix jido.ai.stream_text \"Your prompt here\"")
          System.halt(1)
      end

    model_spec = Keyword.get(opts, :model, "openrouter:openai/gpt-4o-mini")
    quiet = Keyword.get(opts, :quiet, false)
    verbose = Keyword.get(opts, :verbose, false)
    metrics = Keyword.get(opts, :metrics, false)

    if !quiet do
      IO.puts("🚀 Streaming from #{model_spec}")
      IO.puts("Prompt: #{prompt}")
      IO.puts("")
    end

    stream_opts =
      []
      |> maybe_add_option(opts, :system)
      |> maybe_add_option(opts, :max_tokens)
      |> maybe_add_option(opts, :temperature)

    start_time = System.monotonic_time(:millisecond)

    case Jido.AI.stream_text(model_spec, prompt, stream_opts) do
      {:ok, stream} ->
        if !quiet, do: IO.puts("Response:")

        chunks = Enum.to_list(stream)

        # Print each chunk
        for {chunk, index} <- Enum.with_index(chunks, 1) do
          cond do
            verbose and not quiet ->
              IO.puts("[#{index}]: #{inspect(chunk)}")

            not quiet ->
              IO.write(chunk)

            true ->
              :ok
          end
        end

        if !quiet, do: IO.puts("")

        if metrics do
          show_key_stats(chunks, start_time, model_spec, prompt)
        end

        if !quiet, do: IO.puts("✅ Completed")

      {:error, error} ->
        IO.puts("❌ Error: #{inspect(error)}")
        System.halt(1)
    end
  end

  defp maybe_add_option(opts_list, parsed_opts, key) do
    case Keyword.get(parsed_opts, key) do
      nil -> opts_list
      value -> Keyword.put(opts_list, key, value)
    end
  end

  defp show_key_stats(chunks, start_time, model_spec, prompt) do
    end_time = System.monotonic_time(:millisecond)
    response_time = end_time - start_time

    full_text = Enum.join(chunks, "")
    output_tokens = TokenCounter.count_tokens(full_text)

    # Get the actual model for proper cost calculation
    case Model.from(model_spec) do
      {:ok, model} ->
        # For streaming, we estimate input tokens and use actual output token count
        input_tokens = TokenCounter.count_tokens(prompt)

        cost = CostCalculator.calculate_cost(model, input_tokens, output_tokens)

        IO.puts("📊 Stats:")
        IO.puts("   Response time: #{response_time}ms")
        IO.puts("   Output tokens: #{output_tokens}")
        IO.puts("   Estimated input tokens: #{input_tokens}")

        case cost do
          nil ->
            IO.puts("   Cost: Not available (no pricing data)")

          cost_breakdown ->
            IO.puts("   Total cost: #{CostCalculator.format_cost(cost_breakdown)}")
            IO.puts("   #{CostCalculator.format_detailed_cost(cost_breakdown)}")
        end

      {:error, _} ->
        # Fallback to old estimation method
        estimated_tokens = estimate_tokens(full_text)
        estimated_cost = calculate_cost(model_spec, estimated_tokens)

        IO.puts("📊 Stats:")
        IO.puts("   Response time: #{response_time}ms")
        IO.puts("   Estimated tokens: #{estimated_tokens}")

        if estimated_cost > 0 do
          IO.puts("   Estimated cost: $#{Float.round(estimated_cost, 6)}")
        else
          IO.puts("   Estimated cost: Unknown")
        end
    end
  end

  defp estimate_tokens(text) do
    max(1, div(String.length(text), 4))
  end

  defp calculate_cost(model_spec, tokens) do
    cost_per_million =
      cond do
        String.contains?(model_spec, "gpt-4o-mini") -> 0.6
        String.contains?(model_spec, "gpt-4o") -> 2.4
        String.contains?(model_spec, "claude-3-5-sonnet") -> 3.0
        String.contains?(model_spec, "claude-3-haiku") -> 0.25
        String.contains?(model_spec, "deepseek") -> 0.28
        true -> 0.0
      end

    tokens / 1_000_000 * cost_per_million
  end
end
