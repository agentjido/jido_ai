defmodule Jido.Eval.Reporter.Console do
  @moduledoc """
  Console reporter for evaluation results.

  Outputs evaluation progress and results to the console using IO.puts.
  Provides formatted display of sample results and evaluation summaries.

  ## Configuration

  No configuration options are required. Output format is optimized
  for human-readable console display.

  ## Examples

      # Used automatically when configured as default reporter
      config = %Jido.Eval.Config{
        reporters: [{Jido.Eval.Reporter.Console, []}]
      }

      # Manual invocation
      Jido.Eval.Reporter.Console.report(:sample, sample_result, [])
      Jido.Eval.Reporter.Console.report(:summary, final_result, [])
  """

  @behaviour Jido.Eval.Reporter

  require Logger

  @doc """
  Report evaluation events to console output.

  ## Parameters

  - `event` - The event type (`:sample`, `:summary`, etc.)
  - `data` - The event data (sample result, summary, etc.)
  - `opts` - Reporter configuration options (currently unused)

  ## Returns

  - `:ok` - Always returns success
  """
  @spec report(atom(), any(), keyword()) :: :ok
  def report(event, data, _opts) do
    if Application.get_env(:ex_unit, :capture_log, false) do
      # Skip output in test environment to avoid interference
      :ok
    else
      case event do
        :sample -> handle_sample(data, [])
        :summary -> handle_summary(data, [])
        _ -> :ok
      end
    end
  end

  @doc """
  Handle individual sample result output.

  Displays sample ID, scores, and any errors in a compact format.

  ## Parameters

  - `sample` - The sample result data
  - `opts` - Configuration options (unused)

  ## Returns

  - `:ok` - Success
  """
  @spec handle_sample(any(), keyword()) :: :ok
  def handle_sample(sample, _opts) do
    sample_id = Map.get(sample, :sample_id, "unknown")
    scores = Map.get(sample, :scores, %{})
    error = Map.get(sample, :error)

    if error do
      IO.puts("✗ Sample #{sample_id}: ERROR - #{error}")
    else
      score_summary = format_scores(scores)
      IO.puts("✓ Sample #{sample_id}: #{score_summary}")
    end

    :ok
  end

  @doc """
  Handle evaluation summary output.

  Displays comprehensive evaluation results including metrics,
  error statistics, and performance data.

  ## Parameters

  - `summary` - The evaluation summary data
  - `opts` - Configuration options (unused)

  ## Returns

  - `:ok` - Success
  """
  @spec handle_summary(any(), keyword()) :: :ok
  def handle_summary(summary, _opts) do
    run_id = Map.get(summary, :run_id, "unknown")
    sample_count = Map.get(summary, :sample_count, 0)
    completed_count = Map.get(summary, :completed_count, 0)
    error_count = Map.get(summary, :error_count, 0)
    duration_ms = Map.get(summary, :duration_ms, 0)
    pass_rate = Map.get(summary, :pass_rate)

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("EVALUATION SUMMARY")
    IO.puts(String.duplicate("=", 60))
    IO.puts("Run ID: #{run_id}")
    IO.puts("Samples: #{completed_count}/#{sample_count} completed")
    IO.puts("Duration: #{duration_ms}ms")

    if error_count > 0 do
      IO.puts("Errors: #{error_count}")
    end

    if pass_rate do
      IO.puts("Pass Rate: #{Float.round(pass_rate * 100, 2)}%")
    end

    # Display summary statistics if available
    summary_stats = Map.get(summary, :summary_stats, %{})

    if map_size(summary_stats) > 0 do
      IO.puts("\nMetric Scores:")

      Enum.each(summary_stats, fn {metric, stats} ->
        avg = Map.get(stats, :avg, "N/A")
        min = Map.get(stats, :min, "N/A")
        max = Map.get(stats, :max, "N/A")

        IO.puts(
          "  #{metric}: avg=#{format_number(avg)} min=#{format_number(min)} max=#{format_number(max)}"
        )
      end)
    end

    # Display error categories if any
    error_categories = Map.get(summary, :error_categories, %{})

    if map_size(error_categories) > 0 do
      IO.puts("\nError Categories:")

      Enum.each(error_categories, fn {category, count} ->
        IO.puts("  #{category}: #{count}")
      end)
    end

    IO.puts(String.duplicate("=", 60) <> "\n")
    :ok
  end

  # Private helper functions

  defp format_scores(scores) when scores == %{}, do: "no scores"

  defp format_scores(scores) do
    scores
    |> Enum.map(fn {metric, score} -> "#{metric}=#{format_number(score)}" end)
    |> Enum.join(", ")
  end

  defp format_number(num) when is_number(num), do: :erlang.float_to_binary(num * 1.0, decimals: 3)
  defp format_number(other), do: inspect(other)
end
