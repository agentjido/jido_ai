# RLM Lua Plan Forced Test
# Run with: mix run scripts/test_lua_plan.exs
#
# Creates a multi-department dataset and asks a question that requires
# analyzing different regions with different sub-queries — the ideal
# use case for rlm_lua_plan. Uses haiku throughout to keep costs low.

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

defmodule LuaPlanForceAgent do
  use Jido.AI.RLMAgent,
    name: "lua_plan_force",
    description: "Agent that uses Lua-driven orchestration for multi-region analysis",
    model: "anthropic:claude-haiku-4-5",
    recursive_model: "anthropic:claude-haiku-4-5",
    parallel_mode: :llm_driven,
    orchestration_mode: :lua_only,
    chunk_strategy: "lines",
    chunk_size: 700,
    chunk_overlap: 0,
    max_chunks: 12,
    enforce_chunk_defaults: true,
    max_concurrency: 3,
    child_max_iterations: 3,
    child_timeout: 90_000,
    max_chunk_bytes: 80_000,
    max_iterations: 10,
    max_depth: 1,
    extra_tools: []
end

defmodule LuaPlanTelemetry do
  use Agent

  def start_link do
    Agent.start_link(fn -> %{tool_calls: []} end, name: __MODULE__)
  end

  def record_tool(tool_name) when is_binary(tool_name) do
    Agent.update(__MODULE__, fn s -> Map.update!(s, :tool_calls, &[tool_name | &1]) end)
  end

  def tool_calls do
    Agent.get(__MODULE__, fn s -> Enum.reverse(s.tool_calls) end)
  end
end

# --- Telemetry (compact) ---
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
  "lua-plan-trace",
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
            data = get_in(metadata, [:signal, :data]) || %{}
            tool_name = Map.get(data, :tool_name) || Map.get(data, "tool_name") || "?"
            if tool_name != "?", do: LuaPlanTelemetry.record_tool(to_string(tool_name))
            result = get_in(metadata, [:signal, :data, :result])
            preview = result |> inspect() |> String.slice(0, 300)
            IO.puts("\n#{prefix}   #{C.yellow("← #{tool_name}")} #{C.dim(preview)}")

          "react.llm.response" ->
            IO.puts("\n#{prefix}   #{C.cyan("← LLM Response")}")

          type when type not in ["react.usage"] ->
            IO.puts("#{prefix}   #{C.cyan("→ #{type}")}")

          _ ->
            :ok
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

        IO.puts(
          "\n#{prefix} #{C.bold(color.("🏁 DONE"))}" <>
            " reason=#{reason} iters=#{iteration} #{duration_ms}ms"
        )

        if map_size(usage) > 0 do
          inp = usage[:input_tokens] || usage["input_tokens"] || 0
          out = usage[:output_tokens] || usage["output_tokens"] || 0
          IO.puts("#{prefix}   #{C.dim("tokens: #{inp} in / #{out} out")}")
        end

      _ ->
        :ok
    end
  end,
  nil
)

# --- Start Jido ---
{:ok, _} = Jido.start()
{:ok, _} = LuaPlanTelemetry.start_link()

IO.puts(C.green("✓ Jido started"))

# --- Build structured context: 5 departments with buried data ---
departments = [
  {"ENGINEERING", 4_231_500, "Elixir", 47},
  {"SALES", 8_712_300, "Salesforce", 31},
  {"MARKETING", 2_156_800, "HubSpot", 18},
  {"FINANCE", 1_890_200, "SAP", 12},
  {"HR", 967_400, "Workday", 22}
]

sections =
  Enum.map(departments, fn {name, budget, tool, headcount} ->
    header = """
    =====================================
    DEPARTMENT: #{name}
    =====================================
    Budget: $#{budget}
    Primary Tool: #{tool}
    Headcount: #{headcount}
    """

    filler =
      for i <- 1..220 do
        "#{name}-#{i}: metric=#{:rand.uniform(10_000)} status=#{Enum.random(~w(active pending closed))} ts=2025-#{String.pad_leading("#{:rand.uniform(12)}", 2, "0")}-#{String.pad_leading("#{:rand.uniform(28)}", 2, "0")}"
      end

    [header | filler] |> Enum.join("\n")
  end)

context = Enum.join(sections, "\n\n")
context_bytes = byte_size(context)
context_lines = context |> String.split("\n") |> length()

IO.puts("Context: #{context_bytes} bytes / #{context_lines} lines")
IO.puts(C.bold(C.magenta("Model: haiku | max_depth: 1 | mode: llm_driven + lua_only")))

query = """
For each department in this dataset, extract the budget, primary tool, and headcount.

MANDATORY TOOL FLOW:
1) Build a chunk projection first by calling context_chunk.
2) Then call rlm_lua_plan with this exact Lua code:

local plan = {}
for i = 1, math.min(chunk_count, budget.max_total_chunks) do
  plan[#plan + 1] = {
    chunk_ids = {chunks[i].id},
    query = "Extract department name, budget, primary tool, and headcount from this chunk. Return concrete values only."
  }
end
return plan

3) Do not skip rlm_lua_plan.
4) Do not call rlm_spawn_agent directly.

Return a summary table of all five departments.
"""

IO.puts("\n#{C.bold("Query:")} #{C.dim(String.trim(query) |> String.replace("\n", " "))}\n")

explore_start = System.monotonic_time(:millisecond)
{:ok, pid} = Jido.start_agent(Jido.default_instance(), LuaPlanForceAgent)
{:ok, workspace_ref} = LuaPlanForceAgent.create_workspace(pid)
IO.puts(C.green("✓ Agent started\n"))

case LuaPlanForceAgent.explore_sync(pid, String.trim(query),
       context: context,
       workspace_ref: workspace_ref,
       timeout: 300_000
     ) do
  {:ok, result} ->
    elapsed = System.monotonic_time(:millisecond) - explore_start

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts(C.bold(C.green("RESULT")))
    IO.puts(String.duplicate("=", 60))
    IO.puts(result)
    IO.puts(String.duplicate("=", 60))

    checks = [
      {"Engineering $4,231,500",
       String.contains?(to_string(result), "4231500") or String.contains?(to_string(result), "4,231,500")},
      {"Sales $8,712,300",
       String.contains?(to_string(result), "8712300") or String.contains?(to_string(result), "8,712,300")},
      {"Marketing $2,156,800",
       String.contains?(to_string(result), "2156800") or String.contains?(to_string(result), "2,156,800")},
      {"Finance $1,890,200",
       String.contains?(to_string(result), "1890200") or String.contains?(to_string(result), "1,890,200")},
      {"HR $967,400", String.contains?(to_string(result), "967400") or String.contains?(to_string(result), "967,400")}
    ]

    IO.puts("\n#{C.bold("Verification:")}")

    Enum.each(checks, fn {label, found} ->
      IO.puts("  #{label}: #{if found, do: C.green("✓"), else: C.red("✗")}")
    end)

    found_count = Enum.count(checks, fn {_, f} -> f end)
    tool_calls = LuaPlanTelemetry.tool_calls()
    tool_counts = Enum.frequencies(tool_calls)
    workspace = Jido.AI.RLM.WorkspaceStore.get(workspace_ref)
    lua_plans = Map.get(workspace, :lua_plans, [])
    lua_plan_calls = length(lua_plans)

    IO.puts("\n#{C.bold("Stats:")}")
    IO.puts("  Time:     #{elapsed}ms (#{Float.round(elapsed / 1000, 1)}s)")
    IO.puts("  Accuracy: #{found_count}/#{length(checks)}")
    IO.puts("  Lua plan tool calls: #{lua_plan_calls}")

    IO.puts("\n#{C.bold("Tool call counts:")}")

    tool_counts
    |> Enum.sort_by(fn {_tool, count} -> count end, :desc)
    |> Enum.each(fn {tool, count} ->
      IO.puts("  #{String.pad_trailing(tool, 22)} #{count}")
    end)

    if lua_plan_calls == 0 do
      IO.puts(C.red("\n✗ rlm_lua_plan was not used; this run does not validate Lua orchestration"))
    else
      IO.puts(C.green("\n✓ rlm_lua_plan was used in this run"))
    end

  {:error, reason} ->
    elapsed = System.monotonic_time(:millisecond) - explore_start
    tool_calls = LuaPlanTelemetry.tool_calls()
    tool_counts = Enum.frequencies(tool_calls)
    IO.puts("\n#{C.red("Error: #{inspect(reason)}")}")
    IO.puts("  Time: #{elapsed}ms")
    IO.puts("  Tool call counts: #{inspect(tool_counts)}")
end

LuaPlanForceAgent.delete_workspace(pid, workspace_ref)
Jido.stop_agent(Jido.default_instance(), pid)
IO.puts(C.green("\n✓ Done"))
Jido.stop()
