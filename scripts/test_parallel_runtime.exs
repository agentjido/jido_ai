# RLM Pre-Phase Parallel Demo (parallel_mode: :runtime + rlm_lua_plan)
# Run with: mix run scripts/test_parallel_runtime.exs
#
# Tests the deterministic chunk→spawn→synthesize pipeline that bypasses
# the first 2 LLM calls, and also exercises the Lua plan tool via
# a separate llm_driven agent.
#
# Requires valid LLM API keys configured.

Logger.configure(level: :warning)

defmodule C do
  def cyan(text), do: "\e[36m#{text}\e[0m"
  def green(text), do: "\e[32m#{text}\e[0m"
  def yellow(text), do: "\e[33m#{text}\e[0m"
  def magenta(text), do: "\e[35m#{text}\e[0m"
  def red(text), do: "\e[31m#{text}\e[0m"
  def dim(text), do: "\e[2m#{text}\e[0m"
  def bold(text), do: "\e[1m#{text}\e[0m"
end

# ── Agent Definitions ──────────────────────────────────────────────────

defmodule RuntimeParallelAgent do
  @moduledoc "Agent using deterministic runtime parallel mode"
  use Jido.AI.RLMAgent,
    name: "runtime_parallel_demo",
    description: "Deterministic chunk→spawn→synthesize pipeline",
    model: "anthropic:claude-haiku-4-5",
    recursive_model: "anthropic:claude-haiku-4-5",
    parallel_mode: :runtime,
    max_depth: 1,
    max_iterations: 15,
    extra_tools: []
end

defmodule LuaPlanAgent do
  @moduledoc "Agent using LLM-driven mode with Lua plan tool available"
  use Jido.AI.RLMAgent,
    name: "lua_plan_demo",
    description: "LLM-driven agent with Lua plan orchestration",
    model: "anthropic:claude-haiku-4-5",
    recursive_model: "anthropic:claude-haiku-4-5",
    parallel_mode: :llm_driven,
    max_depth: 1,
    max_iterations: 15,
    extra_tools: []
end

# ── Telemetry ──────────────────────────────────────────────────────────

trace_events = [
  [:jido, :agent_server, :signal, :start],
  [:jido, :agent_server, :signal, :stop],
  [:jido, :agent_server, :directive, :start],
  [:jido, :agent_server, :directive, :stop],
  [:jido, :ai, :react, :start],
  [:jido, :ai, :react, :iteration],
  [:jido, :ai, :react, :complete]
]

:telemetry.attach_many(
  "parallel-demo-trace",
  trace_events,
  fn event, measurements, metadata, _config ->
    ts = DateTime.utc_now() |> Calendar.strftime("%H:%M:%S.%f") |> String.slice(0, 12)
    prefix = C.dim("[#{ts}]")

    case event do
      [:jido, :agent_server, :signal, :start] ->
        case metadata[:signal_type] do
          "react.llm.delta" ->
            if delta = get_in(metadata, [:signal, :data, :delta]), do: IO.write(delta)

          "react.tool.result" ->
            tool_name = get_in(metadata, [:signal, :data, :tool_name]) || "?"
            result = get_in(metadata, [:signal, :data, :result])
            preview = result |> inspect() |> String.slice(0, 300)
            IO.puts("\n#{prefix}   #{C.yellow("← #{tool_name}")} #{C.dim(preview)}")

          "react.llm.response" ->
            IO.puts("\n#{prefix}   #{C.cyan("← LLM Response")}")

          type when type not in ["react.usage"] ->
            IO.puts("#{prefix}   #{C.cyan("→ #{type}")}")

          _ -> :ok
        end

      [:jido, :agent_server, :directive, :start] ->
        type = metadata[:directive_type] || "?"
        IO.puts("#{prefix}     #{C.yellow("⚡ #{type}")}")

      [:jido, :agent_server, :directive, :stop] ->
        duration_ms = div(measurements[:duration] || 0, 1_000_000)
        type = metadata[:directive_type] || "?"
        IO.puts("#{prefix}     #{C.yellow("✓ #{type}")} #{C.dim("(#{duration_ms}ms)")}")

      [:jido, :ai, :react, :start] ->
        IO.puts("#{prefix} #{C.bold(C.cyan("🔍 RLM START"))}")

      [:jido, :ai, :react, :iteration] ->
        iteration = metadata[:iteration] || "?"
        IO.puts("\n#{prefix} #{C.bold(C.magenta("🔄 ITERATION #{iteration}"))}")

      [:jido, :ai, :react, :complete] ->
        duration_ms = measurements[:duration] || 0
        iteration = metadata[:iteration] || "?"
        reason = metadata[:termination_reason] || "?"
        usage = metadata[:usage] || %{}
        color = if reason == :final_answer, do: &C.green/1, else: &C.red/1
        IO.puts("\n#{prefix} #{C.bold(color.("🏁 DONE"))}" <>
          " reason=#{reason} iters=#{iteration} #{duration_ms}ms")
        if map_size(usage) > 0 do
          inp = usage[:input_tokens] || usage["input_tokens"] || 0
          out = usage[:output_tokens] || usage["output_tokens"] || 0
          IO.puts("#{prefix}   #{C.dim("tokens: #{inp} in / #{out} out")}")
        end

      _ -> :ok
    end
  end,
  nil
)

# ── Build Test Context ─────────────────────────────────────────────────
# 5 departments with hidden data, similar to test_lua_plan.exs but with
# unique secret codes per department to verify extraction accuracy.

departments = [
  {"ENGINEERING", 4_231_500, "Elixir/OTP", 47, "ENGX-7721"},
  {"SALES", 8_712_300, "Salesforce", 31, "SLSX-4489"},
  {"MARKETING", 2_156_800, "HubSpot", 18, "MKTX-3356"},
  {"FINANCE", 1_890_200, "SAP", 12, "FINX-9912"},
  {"HR", 967_400, "Workday", 22, "HRX-6678"}
]

sections =
  Enum.map(departments, fn {name, budget, tool, headcount, secret_code} ->
    header = """
    =====================================
    DEPARTMENT: #{name}
    =====================================
    Budget: $#{budget}
    Primary Tool: #{tool}
    Headcount: #{headcount}
    Secret Code: #{secret_code}
    """

    filler =
      for i <- 1..500 do
        "#{name}-#{i}: metric=#{:rand.uniform(10_000)} status=#{Enum.random(~w(active pending closed))} ts=2025-#{String.pad_leading("#{:rand.uniform(12)}", 2, "0")}-#{String.pad_leading("#{:rand.uniform(28)}", 2, "0")}"
      end

    [header | filler] |> Enum.join("\n")
  end)

context = Enum.join(sections, "\n\n")
context_bytes = byte_size(context)
context_lines = context |> String.split("\n") |> length()

IO.puts(C.bold("\n" <> String.duplicate("=", 60)))
IO.puts(C.bold("  RLM Pre-Phase Parallel Demo"))
IO.puts(C.bold(String.duplicate("=", 60)))
IO.puts("Context: #{context_bytes} bytes / #{context_lines} lines")
IO.puts("")

# ── Verification helper ────────────────────────────────────────────────

verify = fn result, label ->
  r = to_string(result)

  checks = [
    {"Engineering budget", String.contains?(r, "4231500") or String.contains?(r, "4,231,500")},
    {"Sales budget", String.contains?(r, "8712300") or String.contains?(r, "8,712,300")},
    {"Marketing budget", String.contains?(r, "2156800") or String.contains?(r, "2,156,800")},
    {"Finance budget", String.contains?(r, "1890200") or String.contains?(r, "1,890,200")},
    {"HR budget", String.contains?(r, "967400") or String.contains?(r, "967,400")}
  ]

  IO.puts("\n#{C.bold("Verification (#{label}):")}")
  Enum.each(checks, fn {name, found} ->
    IO.puts("  #{name}: #{if found, do: C.green("✓"), else: C.red("✗")}")
  end)

  found = Enum.count(checks, fn {_, f} -> f end)
  IO.puts("  #{C.bold("Score: #{found}/#{length(checks)}")}")
  found
end

# ── Start Jido ─────────────────────────────────────────────────────────

{:ok, _} = Jido.start()
IO.puts(C.green("✓ Jido started\n"))

query = "For each department, extract the budget, primary tool, headcount, and secret code. Return a summary table."

# ── TEST 1: Runtime Parallel Mode ──────────────────────────────────────

IO.puts(C.bold(C.magenta("━━━ TEST 1: parallel_mode: :runtime ━━━")))
IO.puts(C.dim("Deterministic chunk→spawn→synthesize, no wasted LLM calls"))
IO.puts("")

t1_start = System.monotonic_time(:millisecond)
{:ok, pid1} = Jido.start_agent(Jido.default_instance(), RuntimeParallelAgent)
IO.puts(C.green("✓ RuntimeParallelAgent started"))

case RuntimeParallelAgent.explore_sync(pid1, query,
       context: context,
       timeout: 300_000
     ) do
  {:ok, result} ->
    t1_elapsed = System.monotonic_time(:millisecond) - t1_start

    IO.puts("\n" <> String.duplicate("-", 60))
    IO.puts(C.bold(C.green("RESULT (runtime)")))
    IO.puts(String.duplicate("-", 60))
    IO.puts(result)
    IO.puts(String.duplicate("-", 60))

    verify.(result, "runtime")
    IO.puts("  #{C.bold("Time: #{t1_elapsed}ms (#{Float.round(t1_elapsed / 1000, 1)}s)")}")

  {:error, reason} ->
    t1_elapsed = System.monotonic_time(:millisecond) - t1_start
    IO.puts("\n#{C.red("Error (runtime): #{inspect(reason)}")}")
    IO.puts("  Time: #{t1_elapsed}ms")
end

Jido.stop_agent(Jido.default_instance(), pid1)
IO.puts(C.green("✓ RuntimeParallelAgent stopped\n"))

# ── TEST 2: LLM-Driven with Lua Plan ──────────────────────────────────

IO.puts(C.bold(C.magenta("━━━ TEST 2: parallel_mode: :llm_driven + rlm_lua_plan ━━━")))
IO.puts(C.dim("LLM chooses tools; instructed to use rlm_lua_plan for orchestration"))
IO.puts("")

lua_query = """
For each department in this dataset, extract the budget, primary tool, headcount, and secret code.

IMPORTANT: After chunking, use the rlm_lua_plan tool to write a Lua script that inspects chunk previews
to identify which chunks contain department headers (look for "DEPARTMENT:" in previews), then creates
a plan to analyze each department with a targeted query. Do NOT use rlm_spawn_agent directly — use
rlm_lua_plan for the orchestration.

Return a summary table of all five departments.
"""

t2_start = System.monotonic_time(:millisecond)
{:ok, pid2} = Jido.start_agent(Jido.default_instance(), LuaPlanAgent)
IO.puts(C.green("✓ LuaPlanAgent started"))

case LuaPlanAgent.explore_sync(pid2, String.trim(lua_query),
       context: context,
       timeout: 300_000
     ) do
  {:ok, result} ->
    t2_elapsed = System.monotonic_time(:millisecond) - t2_start

    IO.puts("\n" <> String.duplicate("-", 60))
    IO.puts(C.bold(C.green("RESULT (lua_plan)")))
    IO.puts(String.duplicate("-", 60))
    IO.puts(result)
    IO.puts(String.duplicate("-", 60))

    verify.(result, "lua_plan")
    IO.puts("  #{C.bold("Time: #{t2_elapsed}ms (#{Float.round(t2_elapsed / 1000, 1)}s)")}")

  {:error, reason} ->
    t2_elapsed = System.monotonic_time(:millisecond) - t2_start
    IO.puts("\n#{C.red("Error (lua_plan): #{inspect(reason)}")}")
    IO.puts("  Time: #{t2_elapsed}ms")
end

Jido.stop_agent(Jido.default_instance(), pid2)
IO.puts(C.green("✓ LuaPlanAgent stopped\n"))

# ── Summary ────────────────────────────────────────────────────────────

IO.puts(String.duplicate("=", 60))
IO.puts(C.bold("  DEMO COMPLETE"))
IO.puts(String.duplicate("=", 60))

# ── Cleanup ────────────────────────────────────────────────────────────

Jido.stop()
IO.puts(C.green("✓ Jido stopped"))
