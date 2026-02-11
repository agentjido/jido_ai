# RLM Runtime Parallel Benchmark
# Run with: mix run scripts/bench_parallel_runtime.exs
#
# Measures the deterministic chunk→spawn→synthesize pipeline:
#   - Context size (bytes, lines, estimated tokens)
#   - Agents spawned (chunk count)
#   - Wall-clock time, LLM calls, iterations, accuracy

Logger.configure(level: :warning)

defmodule Bench do
  @moduledoc false

  def cyan(t), do: "\e[36m#{t}\e[0m"
  def green(t), do: "\e[32m#{t}\e[0m"
  def red(t), do: "\e[31m#{t}\e[0m"
  def dim(t), do: "\e[2m#{t}\e[0m"
  def bold(t), do: "\e[1m#{t}\e[0m"

  def fmt_ms(ms) when ms < 1_000, do: "#{ms}ms"
  def fmt_ms(ms), do: "#{Float.round(ms / 1_000, 1)}s"

  def fmt_num(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
    |> Enum.join(",")
  end

  def fmt_num(n), do: inspect(n)

  def estimate_tokens(bytes), do: div(bytes, 4)
end

# ── Agent ──────────────────────────────────────────────────────────────

defmodule BenchRuntimeAgent do
  use Jido.AI.RLMAgent,
    name: "bench_runtime",
    description: "Deterministic chunk→spawn→synthesize pipeline",
    model: "anthropic:claude-haiku-4-5",
    recursive_model: "anthropic:claude-haiku-4-5",
    parallel_mode: :runtime,
    max_depth: 1,
    max_iterations: 15,
    extra_tools: []
end

# ── Telemetry Collector ────────────────────────────────────────────────

defmodule BenchCollector do
  use Agent

  def start_link do
    Agent.start_link(
      fn -> %{token_usage: [], directives: [], llm_calls: 0, iteration_count: 0} end,
      name: __MODULE__
    )
  end

  def record_tokens(usage) do
    Agent.update(__MODULE__, fn s -> Map.update!(s, :token_usage, &[usage | &1]) end)
  end

  def record_directive(type, duration_ms) do
    Agent.update(__MODULE__, fn s ->
      entry = %{type: type, duration_ms: duration_ms, at: System.monotonic_time(:millisecond)}
      Map.update!(s, :directives, &[entry | &1])
    end)
  end

  def inc_llm_calls do
    Agent.update(__MODULE__, fn s -> Map.update!(s, :llm_calls, &(&1 + 1)) end)
  end

  def inc_iterations do
    Agent.update(__MODULE__, fn s -> Map.update!(s, :iteration_count, &(&1 + 1)) end)
  end

  def get_stats, do: Agent.get(__MODULE__, & &1)
end

# ── Telemetry Wiring ───────────────────────────────────────────────────

:telemetry.attach_many(
  "bench-trace",
  [
    [:jido, :agent_server, :signal, :start],
    [:jido, :agent_server, :directive, :stop],
    [:jido, :ai, :react, :iteration]
  ],
  fn event, measurements, metadata, _config ->
    case event do
      [:jido, :agent_server, :signal, :start] ->
        case metadata[:signal_type] do
          "react.usage" ->
            BenchCollector.record_tokens(get_in(metadata, [:signal, :data]) || %{})
          "react.llm.response" ->
            BenchCollector.inc_llm_calls()
          _ -> :ok
        end

      [:jido, :agent_server, :directive, :stop] ->
        duration_ms = div(measurements[:duration] || 0, 1_000_000)
        BenchCollector.record_directive(to_string(metadata[:directive_type] || "unknown"), duration_ms)

      [:jido, :ai, :react, :iteration] ->
        BenchCollector.inc_iterations()

      _ -> :ok
    end
  end,
  nil
)

# ── Context Generator ──────────────────────────────────────────────────

build_context = fn dept_count, filler_lines ->
  departments =
    for i <- 1..dept_count do
      name = Enum.at(~w(ENGINEERING SALES MARKETING FINANCE HR OPERATIONS LEGAL SUPPORT PRODUCT DESIGN), rem(i - 1, 10))
      budget = :rand.uniform(10_000_000)
      tool = Enum.at(~w(Elixir Salesforce HubSpot SAP Workday Jira Confluence Zendesk Figma Notion), rem(i - 1, 10))
      headcount = :rand.uniform(100)
      code = "#{String.slice(name, 0, 3)}X-#{:rand.uniform(9999)}"
      {name, budget, tool, headcount, code}
    end

  sections =
    Enum.map(departments, fn {name, budget, tool, headcount, code} ->
      header = """
      =====================================
      DEPARTMENT: #{name}
      =====================================
      Budget: $#{budget}
      Primary Tool: #{tool}
      Headcount: #{headcount}
      Secret Code: #{code}
      """

      filler =
        for j <- 1..filler_lines do
          "#{name}-#{j}: metric=#{:rand.uniform(10_000)} status=#{Enum.random(~w(active pending closed))} ts=2025-#{String.pad_leading("#{:rand.uniform(12)}", 2, "0")}-#{String.pad_leading("#{:rand.uniform(28)}", 2, "0")}"
        end

      [header | filler] |> Enum.join("\n")
    end)

  context = Enum.join(sections, "\n\n")
  {context, departments}
end

# ── Verification ───────────────────────────────────────────────────────

verify = fn result, departments ->
  r = to_string(result)

  hits =
    Enum.count(departments, fn {_name, budget, _tool, _headcount, _code} ->
      plain = Integer.to_string(budget)
      formatted = Bench.fmt_num(budget)
      String.contains?(r, plain) or String.contains?(r, formatted)
    end)

  {hits, length(departments)}
end

# ── Run Benchmark ──────────────────────────────────────────────────────

{:ok, _} = Jido.start()
{:ok, collector} = BenchCollector.start_link()

dept_count = 5
filler_lines = 500

{context, departments} = build_context.(dept_count, filler_lines)

context_bytes = byte_size(context)
context_lines = context |> String.split("\n") |> length()
est_tokens = Bench.estimate_tokens(context_bytes)

IO.puts(Bench.bold("\n" <> String.duplicate("━", 70)))
IO.puts(Bench.bold("  RLM Runtime Parallel Benchmark"))
IO.puts(Bench.bold(String.duplicate("━", 70)))
IO.puts("")
IO.puts(Bench.bold("Context:"))
IO.puts("  #{Bench.fmt_num(context_bytes)} bytes / #{Bench.fmt_num(context_lines)} lines / ~#{Bench.fmt_num(est_tokens)} tokens")
IO.puts("  #{dept_count} departments × #{filler_lines} filler lines each")
IO.puts("")

query = "For each department, extract the budget, primary tool, headcount, and secret code. Return a summary table."

wall_start = System.monotonic_time(:millisecond)
{:ok, pid} = Jido.start_agent(Jido.default_instance(), BenchRuntimeAgent)

result =
  case BenchRuntimeAgent.explore_sync(pid, query, context: context, timeout: 300_000) do
    {:ok, r} -> r
    {:error, reason} -> "ERROR: #{inspect(reason)}"
  end

wall_ms = System.monotonic_time(:millisecond) - wall_start
Jido.stop_agent(Jido.default_instance(), pid)

# ── Report ─────────────────────────────────────────────────────────────

stats = BenchCollector.get_stats()

get_tok = fn u, key -> Map.get(u, key, 0) + Map.get(u, to_string(key), 0) end
total_input = stats.token_usage |> Enum.map(&get_tok.(&1, :input_tokens)) |> Enum.sum()
total_output = stats.token_usage |> Enum.map(&get_tok.(&1, :output_tokens)) |> Enum.sum()

directives = Enum.sort_by(stats.directives, & &1.at)

phase_labels = ["context_chunk", "rlm_spawn_agent", "synthesize"]
directives =
  directives
  |> Enum.with_index()
  |> Enum.map(fn {d, i} -> Map.put(d, :label, Enum.at(phase_labels, i, d.type)) end)

chunk_ms = Enum.at(directives, 0, %{duration_ms: 0}).duration_ms
spawn_ms = Enum.at(directives, 1, %{duration_ms: 0}).duration_ms
synth_ms = Enum.at(directives, 2, %{duration_ms: 0}).duration_ms

expected_chunks = ceil(context_lines / 1000)
{hits, total_depts} = verify.(result, departments)

IO.puts(Bench.bold(String.duplicate("━", 70)))
IO.puts(Bench.bold("  RESULTS"))
IO.puts(Bench.bold(String.duplicate("━", 70)))

IO.puts("")
IO.puts(Bench.bold("Pipeline Phases:"))
IO.puts("  1. Chunk:         #{Bench.fmt_ms(chunk_ms)}  (context_chunk → split into segments)")
IO.puts("  2. Spawn:         #{Bench.fmt_ms(spawn_ms)}  (rlm_spawn_agent → child agents)")
IO.puts("  3. Synthesize:    #{Bench.fmt_ms(synth_ms)}  (LLM synthesizes child results)")
IO.puts("  ─────────────────")
IO.puts("  Total wall clock: #{Bench.bold(Bench.fmt_ms(wall_ms))}")
IO.puts("")

IO.puts(Bench.bold("Agents:"))
IO.puts("  Parent LLM calls:  #{stats.llm_calls} (synthesis only)")
IO.puts("  Parent iterations:  #{stats.iteration_count}")
IO.puts("  Child agents:       ~#{expected_chunks} (#{Bench.fmt_num(context_lines)} lines ÷ 1000 lines/chunk)")
IO.puts("")

IO.puts(Bench.bold("Directive Trace:"))
Enum.each(directives, fn d ->
  IO.puts("  #{String.pad_trailing(d.label, 25)} #{String.pad_trailing(d.type, 12)} #{Bench.fmt_ms(d.duration_ms)}")
end)
IO.puts("")

IO.puts(Bench.bold("Token Usage (parent agent only):"))
IO.puts("  Input:            #{Bench.fmt_num(total_input)}")
IO.puts("  Output:           #{Bench.fmt_num(total_output)}")
IO.puts("  Total:            #{Bench.fmt_num(total_input + total_output)}")
IO.puts("  #{Bench.dim("Note: child agent tokens not captured by parent telemetry")}")
IO.puts("")

color = if hits == total_depts, do: &Bench.green/1, else: &Bench.red/1
IO.puts(Bench.bold("Accuracy:"))
IO.puts("  Budget extraction: #{color.("#{hits}/#{total_depts}")}")
IO.puts("")

IO.puts(Bench.bold("Answer (truncated to 500 chars):"))
IO.puts(Bench.dim(String.duplicate("-", 70)))
IO.puts(String.slice(result, 0, 500))
if String.length(result) > 500, do: IO.puts(Bench.dim("  ... (#{String.length(result)} chars total)"))
IO.puts(Bench.dim(String.duplicate("-", 70)))

# ── Cleanup ────────────────────────────────────────────────────────────

Agent.stop(collector)
Jido.stop()
IO.puts(Bench.green("✓ Done"))
