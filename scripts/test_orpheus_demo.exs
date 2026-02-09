# Orpheus Dossier Demo - 10M Token RLM Investigation
# Run with: mix run scripts/test_orpheus_demo.exs
#
# Requires valid Anthropic API key configured.

Logger.configure(level: :warning)

defmodule C do
  def cyan(text), do: "\e[36m#{text}\e[0m"
  def green(text), do: "\e[32m#{text}\e[0m"
  def yellow(text), do: "\e[33m#{text}\e[0m"
  def magenta(text), do: "\e[35m#{text}\e[0m"
  def blue(text), do: "\e[34m#{text}\e[0m"
  def red(text), do: "\e[31m#{text}\e[0m"
  def dim(text), do: "\e[2m#{text}\e[0m"
  def bold(text), do: "\e[1m#{text}\e[0m"
end

start_time = System.monotonic_time(:millisecond)

# ── Telemetry ────────────────────────────────────────────────────────

trace_events = [
  [:jido, :agent, :cmd, :start],
  [:jido, :agent, :cmd, :stop],
  [:jido, :agent, :cmd, :exception],
  [:jido, :agent_server, :signal, :start],
  [:jido, :agent_server, :signal, :stop],
  [:jido, :agent_server, :signal, :exception],
  [:jido, :agent_server, :directive, :start],
  [:jido, :agent_server, :directive, :stop],
  [:jido, :agent_server, :directive, :exception],
  [:jido, :agent, :strategy, :cmd, :start],
  [:jido, :agent, :strategy, :cmd, :stop],
  [:jido, :agent, :strategy, :cmd, :exception],
  [:jido, :agent, :strategy, :tick, :start],
  [:jido, :agent, :strategy, :tick, :stop],
  [:jido, :ai, :react, :start],
  [:jido, :ai, :react, :iteration],
  [:jido, :ai, :react, :complete]
]

:telemetry.attach_many(
  "orpheus-debug-trace",
  trace_events,
  fn event, measurements, metadata, _config ->
    ts = DateTime.utc_now() |> Calendar.strftime("%H:%M:%S.%f") |> String.slice(0, 12)
    prefix = C.dim("[#{ts}]")

    case event do
      [:jido, :agent, :cmd, :start] ->
        action = metadata[:action] || "unknown"
        IO.puts("#{prefix} #{C.green("▶ CMD START")} #{inspect(action)}")

      [:jido, :agent, :cmd, :stop] ->
        duration_ms = div(measurements[:duration] || 0, 1_000_000)
        directives = metadata[:directive_count] || 0
        IO.puts("#{prefix} #{C.green("✓ CMD STOP")} #{C.dim("(#{duration_ms}ms, #{directives} directives)")}")

      [:jido, :agent, :cmd, :exception] ->
        duration_ms = div(measurements[:duration] || 0, 1_000_000)
        IO.puts("#{prefix} #{C.red("✗ CMD ERROR")} #{C.dim("(#{duration_ms}ms)")} #{inspect(metadata[:error])}")

      [:jido, :agent_server, :signal, :start] ->
        signal_type = metadata[:signal_type] || "unknown"

        case signal_type do
          "react.llm.delta" ->
            if delta = get_in(metadata, [:signal, :data, :delta]) do
              IO.write(delta)
            end

          "react.tool.result" ->
            IO.puts("\n#{prefix}   #{C.yellow("← Tool Result")} #{C.dim("(completed)")}")

          "react.llm.response" ->
            IO.puts("\n#{prefix}   #{C.cyan("← LLM Response")} #{C.dim("(processing...)")}")

          _ ->
            IO.puts("#{prefix}   #{C.cyan("→ Signal")} #{signal_type}")
        end

      [:jido, :agent_server, :signal, :stop] ->
        signal_type = metadata[:signal_type] || "unknown"
        duration_ms = div(measurements[:duration] || 0, 1_000_000)

        unless signal_type == "react.llm.delta" do
          IO.puts("#{prefix}   #{C.cyan("← Signal")} #{signal_type} #{C.dim("(#{duration_ms}ms)")}")
        end

      [:jido, :agent_server, :signal, :exception] ->
        signal_type = metadata[:signal_type] || "unknown"
        IO.puts("#{prefix}   #{C.red("✗ Signal ERROR")} #{signal_type}: #{inspect(metadata[:error])}")

      [:jido, :agent_server, :directive, :start] ->
        directive_type = metadata[:directive_type] || "unknown"
        IO.puts("#{prefix}     #{C.yellow("⚡ Directive")} #{directive_type}")

      [:jido, :agent_server, :directive, :stop] ->
        duration_ms = div(measurements[:duration] || 0, 1_000_000)
        directive_type = metadata[:directive_type] || "unknown"
        IO.puts("#{prefix}     #{C.yellow("✓ Directive")} #{directive_type} #{C.dim("(#{duration_ms}ms)")}")

      [:jido, :agent_server, :directive, :exception] ->
        directive_type = metadata[:directive_type] || "unknown"
        IO.puts("#{prefix}     #{C.red("✗ Directive ERROR")} #{directive_type}: #{inspect(metadata[:error])}")

      [:jido, :agent, :strategy, :cmd, :start] ->
        strategy = metadata[:strategy] || "?"
        IO.puts("#{prefix}   #{C.magenta("▸ Strategy CMD")} #{strategy}")

      [:jido, :agent, :strategy, :cmd, :stop] ->
        duration_ms = div(measurements[:duration] || 0, 1_000_000)
        directives = metadata[:directive_count] || 0
        IO.puts("#{prefix}   #{C.magenta("◂ Strategy CMD")} #{C.dim("(#{duration_ms}ms, #{directives} directives)")}")

      [:jido, :agent, :strategy, :cmd, :exception] ->
        IO.puts("#{prefix}   #{C.red("✗ Strategy ERROR")} #{inspect(metadata[:error])}")

      [:jido, :agent, :strategy, :tick, :start] ->
        IO.puts("#{prefix}   #{C.blue("⟳ Strategy TICK")}")

      [:jido, :agent, :strategy, :tick, :stop] ->
        duration_ms = div(measurements[:duration] || 0, 1_000_000)
        IO.puts("#{prefix}   #{C.blue("⟲ Strategy TICK")} #{C.dim("(#{duration_ms}ms)")}")

      [:jido, :ai, :react, :start] ->
        IO.puts("#{prefix} #{C.bold(C.cyan("🔍 ORPHEUS INVESTIGATION STARTED"))}")

      [:jido, :ai, :react, :iteration] ->
        iteration = metadata[:iteration] || "?"
        call_id = metadata[:call_id] || "?"
        IO.puts("\n#{prefix} #{C.bold(C.magenta("🔄 ITERATION #{iteration}"))}" <>
          " #{C.dim("call_id=#{String.slice(call_id, 0, 8)}...")}")

      [:jido, :ai, :react, :complete] ->
        duration_ms = measurements[:duration] || 0
        iteration = metadata[:iteration] || "?"
        reason = metadata[:termination_reason] || "?"
        usage = metadata[:usage] || %{}

        color = if reason == :final_answer, do: &C.green/1, else: &C.red/1
        IO.puts("\n#{prefix} #{C.bold(color.("🏁 INVESTIGATION COMPLETE"))}" <>
          " reason=#{reason} iterations=#{iteration} duration=#{duration_ms}ms")

        if map_size(usage) > 0 do
          input = usage[:input_tokens] || usage["input_tokens"] || 0
          output = usage[:output_tokens] || usage["output_tokens"] || 0
          IO.puts("#{prefix}   #{C.dim("tokens: input=#{input} output=#{output}")}")
        end

      _ ->
        :ok
    end
  end,
  nil
)

# ── Generate context ─────────────────────────────────────────────────

IO.puts(C.bold(C.cyan("╔══════════════════════════════════════════════════════════╗")))
IO.puts(C.bold(C.cyan("║        PROJECT ORPHEUS - 10M TOKEN INVESTIGATION        ║")))
IO.puts(C.bold(C.cyan("╚══════════════════════════════════════════════════════════╝")))
IO.puts("")

IO.puts("#{C.dim("Generating Orpheus Dossier (~40 MB)...")}")
gen_start = System.monotonic_time(:millisecond)

context = Jido.AI.Examples.OrpheusDossier.generate()

gen_elapsed = System.monotonic_time(:millisecond) - gen_start
context_bytes = byte_size(context)
estimated_tokens = div(context_bytes, 4)
doc_count = context |> String.split("=== DOCUMENT #") |> length() |> Kernel.-(1)

IO.puts(C.green("✓ Dossier generated in #{gen_elapsed}ms"))
IO.puts("  Size:       #{Float.round(context_bytes / 1_000_000, 1)} MB (#{context_bytes} bytes)")
IO.puts("  Documents:  ~#{doc_count}")
IO.puts("  Est tokens: ~#{div(estimated_tokens, 1_000_000)}M (#{estimated_tokens})")
IO.puts("")
IO.puts(C.bold(C.yellow("Expected answer: #{Jido.AI.Examples.OrpheusDossier.expected_answer()}")))
IO.puts(C.bold(C.yellow("Saboteur:        #{Jido.AI.Examples.OrpheusDossier.saboteur()}")))
IO.puts("")

# ── Start agent ──────────────────────────────────────────────────────

alias Jido.AI.Examples.OrpheusAgent

{:ok, _} = Jido.start()
IO.puts(C.green("✓ Jido started"))

{:ok, pid} = Jido.start_agent(Jido.default_instance(), OrpheusAgent)
IO.puts(C.green("✓ Agent started: #{inspect(pid)}"))
IO.puts("")

query = """
You are an investigator analyzing the Project ORPHEUS incident dossier.

Determine:
1. Who sabotaged the ORPHEUS system?
2. What was their motive?
3. Compute the ORPHEUS emergency override phrase using the recovery protocol found in the dossier.

For the override phrase, you MUST find the official recovery protocol document and follow its instructions exactly to derive each word from the specified organizational sources.

Provide the final override phrase and cite which documents contained the protocol and each required fragment.
"""

IO.puts(C.bold("Starting investigation...\n"))
IO.puts(String.duplicate("─", 60))
explore_start = System.monotonic_time(:millisecond)

case OrpheusAgent.explore_sync(pid, query,
       context: context,
       timeout: 600_000
     ) do
  {:ok, result} ->
    explore_elapsed = System.monotonic_time(:millisecond) - explore_start
    total_elapsed = System.monotonic_time(:millisecond) - start_time

    expected = Jido.AI.Examples.OrpheusDossier.expected_answer()
    result_str = to_string(result)
    found_phrase = String.contains?(result_str, expected)
    found_saboteur = String.contains?(result_str, "Vasquez")
    found_cardinal = String.contains?(String.upcase(result_str), "CARDINAL")
    found_autumn = String.contains?(String.upcase(result_str), "AUTUMN")
    found_seven = String.contains?(String.upcase(result_str), "SEVEN")
    found_forge = String.contains?(String.upcase(result_str), "FORGE")

    IO.puts("\n" <> String.duplicate("═", 60))
    IO.puts(C.bold(C.green("INVESTIGATION RESULT")))
    IO.puts(String.duplicate("═", 60))
    IO.puts(result_str)
    IO.puts(String.duplicate("═", 60))
    IO.puts("")
    IO.puts(C.bold("Scorecard:"))
    IO.puts("  Exact phrase match:  #{if found_phrase, do: C.green("✓ YES"), else: C.red("✗ NO")}")
    IO.puts("  Saboteur identified: #{if found_saboteur, do: C.green("✓ YES"), else: C.red("✗ NO")}")
    IO.puts("  Word 1 (CARDINAL):   #{if found_cardinal, do: C.green("✓"), else: C.red("✗")}")
    IO.puts("  Word 2 (AUTUMN):     #{if found_autumn, do: C.green("✓"), else: C.red("✗")}")
    IO.puts("  Word 3 (SEVEN):      #{if found_seven, do: C.green("✓"), else: C.red("✗")}")
    IO.puts("  Word 4 (FORGE):      #{if found_forge, do: C.green("✓"), else: C.red("✗")}")
    IO.puts("")
    IO.puts(C.bold("Performance:"))
    IO.puts("  Context:         #{Float.round(context_bytes / 1_000_000, 1)} MB / ~#{doc_count} docs / ~#{div(estimated_tokens, 1_000_000)}M tokens")
    IO.puts("  Generation:      #{gen_elapsed}ms")
    IO.puts("  Explore time:    #{explore_elapsed}ms (#{Float.round(explore_elapsed / 1000, 1)}s)")
    IO.puts("  Total wall time: #{total_elapsed}ms (#{Float.round(total_elapsed / 1000, 1)}s)")

  {:error, reason} ->
    explore_elapsed = System.monotonic_time(:millisecond) - explore_start
    total_elapsed = System.monotonic_time(:millisecond) - start_time

    IO.puts("\n" <> C.red("Error: #{inspect(reason)}"))
    IO.puts("")
    IO.puts(C.bold("Performance:"))
    IO.puts("  Context:         #{Float.round(context_bytes / 1_000_000, 1)} MB / ~#{doc_count} docs / ~#{div(estimated_tokens, 1_000_000)}M tokens")
    IO.puts("  Generation:      #{gen_elapsed}ms")
    IO.puts("  Explore time:    #{explore_elapsed}ms (#{Float.round(explore_elapsed / 1000, 1)}s)")
    IO.puts("  Total wall time: #{total_elapsed}ms (#{Float.round(total_elapsed / 1000, 1)}s)")
end

Jido.stop_agent(Jido.default_instance(), pid)
IO.puts(C.green("✓ Agent stopped"))
Jido.stop()
IO.puts(C.green("✓ Jido stopped"))
