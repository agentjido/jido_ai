defmodule JidoAI.Bench.ReAct.Report do
  @moduledoc false

  def print_summary(reports) do
    IO.puts("\nState-growth summary")

    IO.puts("requested | status | model calls | executed tool rounds | largest fact items | error items | elapsed ms")

    Enum.each(reports, fn report ->
      IO.puts(
        Enum.join(
          [
            report.requested_rounds,
            report.status,
            report.model_calls,
            report.executed_tool_rounds,
            report.largest_fact_items,
            report.error_item_count || "-",
            report.elapsed_ms
          ],
          " | "
        )
      )

      IO.puts("  largest shape at round #{report.largest_fact_round}: #{report.largest_fact_shape}")
      IO.puts("  child items: #{inspect(report.largest_fact_child_items)}")

      if report.error do
        IO.puts("  error: #{report.error}")
      end
    end)
  end

  def print_rounds(report) do
    IO.puts("\n#{report.requested_rounds}-round probe facts")
    IO.puts("round | facts | largest items | largest external bytes")

    report.fact_rounds
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.each(fn {round, metrics} ->
      IO.puts(
        Enum.join(
          [round, metrics.fact_count, metrics.largest_items, metrics.largest_external_bytes],
          " | "
        )
      )
    end)
  end

  def print_memory(report) do
    memory = report.vm_memory

    IO.puts("ReAct VM memory")
    IO.puts("requested rounds: #{report.requested_rounds}")
    IO.puts("status: #{report.status}")
    IO.puts("model calls: #{report.model_calls}")
    IO.puts("tool rounds: #{report.executed_tool_rounds}")
    IO.puts("elapsed ms: #{report.elapsed_ms}")
    IO.puts("samples: #{memory.samples}")
    IO.puts("memory bytes: baseline | peak | increase | final")

    Enum.each([:total, :processes, :binary, :ets], fn key ->
      IO.puts(
        "#{key}: #{memory.baseline[key]} | #{memory.peak[key]} | " <>
          "#{memory.peak_increase[key]} | #{memory.final[key]}"
      )
    end)

    if report.error, do: IO.puts("error: #{report.error}")

    IO.puts("largest processes at peak:")
    Enum.each(memory.top_at_peak, &IO.inspect/1)
  end
end
