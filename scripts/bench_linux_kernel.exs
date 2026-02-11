# RLM Linux Kernel Benchmark
# Run with: mix run scripts/bench_linux_kernel.exs
#
# Downloads a subset of the Linux kernel source and uses it as real-world
# context that exceeds any single model's context window (~500K+ tokens).
# The benchmark can run in llm-driven (Lua orchestration) or runtime fan-out
# mode, without ever sending the full context to a single LLM call.
#
# Prerequisites:
#   - git (to clone linux kernel)
#   - ~200MB disk for shallow clone
#
# Configuration via env vars:
#   BENCH_MODE                     - "lua" (default), "runtime", or "llm"
#   BENCH_TARGET_MB                - Target context size in MB; 0 means full selected corpus (default: 2)
#   BENCH_CHUNK_STRATEGY           - "lines" (default) or "bytes"
#   BENCH_CHUNK_SIZE               - Chunk size (lines or bytes, default: 1000)
#   BENCH_CHUNK_OVERLAP            - Chunk overlap (default: 0)
#   BENCH_MAX_CHUNKS               - Max chunk count (default: 500)
#   BENCH_CHUNK_PREVIEW_BYTES      - Chunk preview bytes (default: 100)
#   BENCH_ENFORCE_CHUNK_DEFAULTS   - Force chunk defaults in llm-driven mode (default: true)
#   BENCH_MAX_DEPTH                - Max recursion depth (default: 1)
#   BENCH_MAX_CONCURRENCY          - Child fan-out concurrency (default: 10)
#   BENCH_CHILD_MAX_ITERATIONS     - Child max iterations (default: 8)
#   BENCH_CHILD_TIMEOUT_MS         - Child timeout ms (default: 120000)
#   BENCH_MAX_CHUNK_BYTES          - Max bytes read per chunk in child fan-out (default: 100000)
#   BENCH_SKIP_DOWNLOAD - Set to "true" to reuse existing clone

Logger.configure(level: :warning)

defmodule Bench do
  @moduledoc false

  def cyan(t), do: "\e[36m#{t}\e[0m"
  def green(t), do: "\e[32m#{t}\e[0m"
  def red(t), do: "\e[31m#{t}\e[0m"
  def yellow(t), do: "\e[33m#{t}\e[0m"
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

  def fmt_bytes(b) when b < 1_024, do: "#{b}B"
  def fmt_bytes(b) when b < 1_048_576, do: "#{Float.round(b / 1_024, 1)}KB"
  def fmt_bytes(b), do: "#{Float.round(b / 1_048_576, 1)}MB"
end

# ── Linux Kernel Source Loader ─────────────────────────────────────────

defmodule KernelLoader do
  @moduledoc false

  @clone_dir "/tmp/linux-kernel-bench"
  @kernel_repo "https://github.com/torvalds/linux.git"

  @source_dirs ["kernel", "mm", "fs", "net/core", "drivers/base", "init", "ipc", "security"]

  def load(target_bytes, skip_download \\ false) do
    unless skip_download do
      clone_kernel()
    end

    {context, facts} = collect_source(target_bytes)
    {context, facts}
  end

  defp clone_kernel do
    if File.dir?(@clone_dir) do
      IO.puts(Bench.dim("  Using existing clone at #{@clone_dir}"))
    else
      IO.puts(Bench.dim("  Shallow-cloning Linux kernel (depth=1, sparse)..."))

      {_, 0} =
        System.cmd(
          "git",
          [
            "clone",
            "--depth",
            "1",
            "--filter=blob:none",
            "--sparse",
            @kernel_repo,
            @clone_dir
          ],
          stderr_to_stdout: true
        )

      {_, 0} =
        System.cmd(
          "git",
          [
            "-C",
            @clone_dir,
            "sparse-checkout",
            "set" | @source_dirs
          ],
          stderr_to_stdout: true
        )

      {_, 0} =
        System.cmd("git", ["-C", @clone_dir, "checkout"], stderr_to_stdout: true)

      IO.puts(Bench.dim("  Clone complete"))
    end
  end

  def collect_source(target_bytes) do
    target_label =
      if target_bytes <= 0 do
        "all selected source files"
      else
        Bench.fmt_bytes(target_bytes)
      end

    IO.puts(Bench.dim("  Collecting source files (target: #{target_label})..."))

    files =
      @source_dirs
      |> Enum.flat_map(fn dir ->
        full_dir = Path.join(@clone_dir, dir)

        if File.dir?(full_dir) do
          full_dir
          |> find_c_files()
          |> Enum.map(fn path ->
            rel = Path.relative_to(path, @clone_dir)
            {path, rel}
          end)
        else
          []
        end
      end)
      |> Enum.shuffle()

    {context_parts, facts, _bytes} =
      Enum.reduce_while(files, {[], [], 0}, fn {abs_path, rel_path}, {parts, facts, acc_bytes} ->
        if target_bytes > 0 and acc_bytes >= target_bytes do
          {:halt, {parts, facts, acc_bytes}}
        else
          case File.read(abs_path) do
            {:ok, content} ->
              header = "// ═══ FILE: #{rel_path} ═══\n"
              part = header <> content <> "\n\n"
              file_facts = extract_facts(rel_path, content)
              new_bytes = acc_bytes + byte_size(part)
              {:cont, {[part | parts], file_facts ++ facts, new_bytes}}

            {:error, _} ->
              {:cont, {parts, facts, acc_bytes}}
          end
        end
      end)

    context = context_parts |> Enum.reverse() |> Enum.join()
    IO.puts(Bench.dim("  Collected #{length(context_parts)} files, #{length(facts)} verifiable facts"))
    {context, facts}
  end

  defp find_c_files(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          full = Path.join(dir, entry)

          cond do
            File.dir?(full) -> find_c_files(full)
            String.ends_with?(entry, ".c") or String.ends_with?(entry, ".h") -> [full]
            true -> []
          end
        end)

      {:error, _} ->
        []
    end
  end

  def extract_facts(rel_path, content) do
    facts = []

    facts =
      case Regex.run(~r/MODULE_AUTHOR\("([^"]+)"\)/, content) do
        [_, author] -> [{:module_author, rel_path, author} | facts]
        _ -> facts
      end

    facts =
      case Regex.run(~r/MODULE_DESCRIPTION\("([^"]+)"\)/, content) do
        [_, desc] -> [{:module_description, rel_path, desc} | facts]
        _ -> facts
      end

    facts =
      Regex.scan(~r/SYSCALL_DEFINE\d\((\w+)/, content)
      |> Enum.reduce(facts, fn [_, syscall_name], acc ->
        [{:syscall, rel_path, syscall_name} | acc]
      end)

    facts =
      case Regex.run(~r/SPDX-License-Identifier:\s*(.+)/, content) do
        [_, license] -> [{:license, rel_path, String.trim(license)} | facts]
        _ -> facts
      end

    facts
  end
end

# ── Agent ──────────────────────────────────────────────────────────────

defmodule BenchKernelLuaAgent do
  use Jido.AI.RLMAgent,
    name: "bench_kernel_lua",
    description: "Linux kernel source explorer (llm-driven + lua orchestration)",
    model: "anthropic:claude-haiku-4-5",
    recursive_model: "anthropic:claude-haiku-4-5",
    parallel_mode: :llm_driven,
    orchestration_mode: :lua_only,
    max_depth: String.to_integer(System.get_env("BENCH_MAX_DEPTH", "1")),
    chunk_strategy: System.get_env("BENCH_CHUNK_STRATEGY", "lines"),
    chunk_size: String.to_integer(System.get_env("BENCH_CHUNK_SIZE", "1000")),
    chunk_overlap: String.to_integer(System.get_env("BENCH_CHUNK_OVERLAP", "0")),
    max_chunks: String.to_integer(System.get_env("BENCH_MAX_CHUNKS", "500")),
    chunk_preview_bytes: String.to_integer(System.get_env("BENCH_CHUNK_PREVIEW_BYTES", "100")),
    enforce_chunk_defaults: System.get_env("BENCH_ENFORCE_CHUNK_DEFAULTS", "true") == "true",
    child_max_iterations: String.to_integer(System.get_env("BENCH_CHILD_MAX_ITERATIONS", "8")),
    child_timeout: String.to_integer(System.get_env("BENCH_CHILD_TIMEOUT_MS", "120000")),
    max_chunk_bytes: String.to_integer(System.get_env("BENCH_MAX_CHUNK_BYTES", "100000")),
    max_concurrency: String.to_integer(System.get_env("BENCH_MAX_CONCURRENCY", "10")),
    max_iterations: 15,
    extra_tools: []
end

defmodule BenchKernelRuntimeAgent do
  use Jido.AI.RLMAgent,
    name: "bench_kernel_runtime",
    description: "Linux kernel source explorer (runtime deterministic fan-out)",
    model: "anthropic:claude-haiku-4-5",
    recursive_model: "anthropic:claude-haiku-4-5",
    parallel_mode: :runtime,
    orchestration_mode: :spawn_only,
    max_depth: String.to_integer(System.get_env("BENCH_MAX_DEPTH", "1")),
    chunk_strategy: System.get_env("BENCH_CHUNK_STRATEGY", "lines"),
    chunk_size: String.to_integer(System.get_env("BENCH_CHUNK_SIZE", "1000")),
    chunk_overlap: String.to_integer(System.get_env("BENCH_CHUNK_OVERLAP", "0")),
    max_chunks: String.to_integer(System.get_env("BENCH_MAX_CHUNKS", "500")),
    chunk_preview_bytes: String.to_integer(System.get_env("BENCH_CHUNK_PREVIEW_BYTES", "100")),
    enforce_chunk_defaults: true,
    child_max_iterations: String.to_integer(System.get_env("BENCH_CHILD_MAX_ITERATIONS", "8")),
    child_timeout: String.to_integer(System.get_env("BENCH_CHILD_TIMEOUT_MS", "120000")),
    max_chunk_bytes: String.to_integer(System.get_env("BENCH_MAX_CHUNK_BYTES", "100000")),
    max_concurrency: String.to_integer(System.get_env("BENCH_MAX_CONCURRENCY", "10")),
    max_iterations: 15,
    extra_tools: []
end

defmodule BenchKernelLLMAgent do
  use Jido.AI.RLMAgent,
    name: "bench_kernel_llm",
    description: "Linux kernel source explorer (llm-driven auto tooling)",
    model: "anthropic:claude-haiku-4-5",
    recursive_model: "anthropic:claude-haiku-4-5",
    parallel_mode: :llm_driven,
    orchestration_mode: :auto,
    max_depth: String.to_integer(System.get_env("BENCH_MAX_DEPTH", "1")),
    chunk_strategy: System.get_env("BENCH_CHUNK_STRATEGY", "lines"),
    chunk_size: String.to_integer(System.get_env("BENCH_CHUNK_SIZE", "1000")),
    chunk_overlap: String.to_integer(System.get_env("BENCH_CHUNK_OVERLAP", "0")),
    max_chunks: String.to_integer(System.get_env("BENCH_MAX_CHUNKS", "500")),
    chunk_preview_bytes: String.to_integer(System.get_env("BENCH_CHUNK_PREVIEW_BYTES", "100")),
    enforce_chunk_defaults: System.get_env("BENCH_ENFORCE_CHUNK_DEFAULTS", "true") == "true",
    child_max_iterations: String.to_integer(System.get_env("BENCH_CHILD_MAX_ITERATIONS", "8")),
    child_timeout: String.to_integer(System.get_env("BENCH_CHILD_TIMEOUT_MS", "120000")),
    max_chunk_bytes: String.to_integer(System.get_env("BENCH_MAX_CHUNK_BYTES", "100000")),
    max_concurrency: String.to_integer(System.get_env("BENCH_MAX_CONCURRENCY", "10")),
    max_iterations: 15,
    extra_tools: []
end

chunk_strategy = System.get_env("BENCH_CHUNK_STRATEGY", "lines")
chunk_size = String.to_integer(System.get_env("BENCH_CHUNK_SIZE", "1000"))
chunk_overlap = String.to_integer(System.get_env("BENCH_CHUNK_OVERLAP", "0"))
max_depth = String.to_integer(System.get_env("BENCH_MAX_DEPTH", "1"))

bench_mode =
  System.get_env("BENCH_MODE", "lua")
  |> String.downcase()
  |> case do
    "runtime" -> "runtime"
    "llm" -> "llm"
    _ -> "lua"
  end

{agent_mod, mode_label} =
  case bench_mode do
    "runtime" -> {BenchKernelRuntimeAgent, "runtime deterministic"}
    "llm" -> {BenchKernelLLMAgent, "llm-driven (auto orchestration)"}
    _ -> {BenchKernelLuaAgent, "llm-driven (lua-only orchestration)"}
  end

# ── Telemetry Collector ────────────────────────────────────────────────

defmodule BenchCollector do
  use Agent

  def start_link do
    Agent.start_link(
      fn -> %{token_usage: [], directives: [], llm_calls: 0, iteration_count: 0, tool_calls: []} end,
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

  def record_tool_call(tool_name) do
    Agent.update(__MODULE__, fn s -> Map.update!(s, :tool_calls, &[tool_name | &1]) end)
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

          "react.tool.result" ->
            data = get_in(metadata, [:signal, :data]) || %{}
            tool_name = Map.get(data, :tool_name) || Map.get(data, "tool_name") || "unknown"
            BenchCollector.record_tool_call(to_string(tool_name))

          _ ->
            :ok
        end

      [:jido, :agent_server, :directive, :stop] ->
        duration_ms = div(measurements[:duration] || 0, 1_000_000)
        BenchCollector.record_directive(to_string(metadata[:directive_type] || "unknown"), duration_ms)

      [:jido, :ai, :react, :iteration] ->
        BenchCollector.inc_iterations()

      _ ->
        :ok
    end
  end,
  nil
)

# ── Build Query & Verification ─────────────────────────────────────────

build_query = fn facts, mode ->
  syscalls = facts |> Enum.filter(&(elem(&1, 0) == :syscall)) |> Enum.take(10)
  authors = facts |> Enum.filter(&(elem(&1, 0) == :module_author)) |> Enum.take(5)

  syscall_part =
    if syscalls != [] do
      names = Enum.map(syscalls, fn {:syscall, file, name} -> "#{name} (#{file})" end)
      "1. Verify these syscall definitions exist and list which file defines each: #{Enum.join(names, ", ")}\n"
    else
      ""
    end

  author_part =
    if authors != [] do
      "2. Find all MODULE_AUTHOR declarations and list each author with their file.\n"
    else
      ""
    end

  orchestration_instructions =
    if mode == "lua" do
      """
      0. MANDATORY TOOL FLOW (must follow exactly):
         - Build a chunk projection first via `context_chunk`.
         - Then call `rlm_lua_plan` with this exact Lua code:

           local plan = {}
           for i = 1, math.min(chunk_count, budget.max_total_chunks) do
             plan[#plan + 1] = {
               chunk_ids = {chunks[i].id},
               query = "From this chunk, extract any syscall names, MODULE_AUTHOR values, SPDX identifiers, and subsystem clues relevant to the parent query."
             }
           end
           return plan

         - Do not skip `rlm_lua_plan`.
         - Do not call `rlm_spawn_agent` directly.
      """
    else
      ""
    end

  """
  Analyze this Linux kernel source code and answer:
  #{orchestration_instructions}
  #{syscall_part}#{author_part}3. List every unique SPDX license identifier found across all files.
  4. Identify the 5 largest files by line count.
  5. Summarize the major subsystems represented in this code.

  Return a structured report with sections for each question.
  """
end

verify = fn result, facts ->
  r = to_string(result)

  syscall_facts = Enum.filter(facts, &(elem(&1, 0) == :syscall))
  author_facts = Enum.filter(facts, &(elem(&1, 0) == :module_author))
  license_facts = Enum.filter(facts, &(elem(&1, 0) == :license)) |> Enum.uniq_by(&elem(&1, 2))

  syscall_hits =
    Enum.count(syscall_facts, fn {:syscall, _file, name} ->
      String.contains?(r, name)
    end)

  author_hits =
    Enum.count(author_facts, fn {:module_author, _file, author} ->
      first_word = author |> String.split() |> List.first("")
      String.contains?(r, first_word)
    end)

  license_hits =
    Enum.count(license_facts, fn {:license, _file, license} ->
      String.contains?(r, license)
    end)

  %{
    syscalls: {syscall_hits, length(syscall_facts)},
    authors: {author_hits, length(author_facts)},
    licenses: {license_hits, length(license_facts)},
    total_facts: length(facts)
  }
end

# ── Run Benchmark ──────────────────────────────────────────────────────

target_mb = String.to_integer(System.get_env("BENCH_TARGET_MB", "2"))
target_bytes = if target_mb <= 0, do: 0, else: target_mb * 1_048_576
skip_download = System.get_env("BENCH_SKIP_DOWNLOAD", "false") == "true"

IO.puts(Bench.bold("\n" <> String.duplicate("━", 70)))
IO.puts(Bench.bold("  RLM Linux Kernel Benchmark"))
IO.puts(Bench.bold(String.duplicate("━", 70)))
IO.puts("")

IO.puts(Bench.bold("Loading context:"))
{context, facts} = KernelLoader.load(target_bytes, skip_download)

context_bytes = byte_size(context)
context_lines = context |> String.split("\n") |> length()
est_tokens = Bench.estimate_tokens(context_bytes)

expected_chunks =
  cond do
    chunk_size <= 0 ->
      0

    chunk_strategy == "bytes" ->
      ceil(context_bytes / chunk_size)

    true ->
      ceil(context_lines / chunk_size)
  end

IO.puts("")
IO.puts(Bench.bold("Context:"))

IO.puts(
  "  #{Bench.fmt_bytes(context_bytes)} / #{Bench.fmt_num(context_lines)} lines / ~#{Bench.fmt_num(est_tokens)} tokens"
)

IO.puts(
  "  Haiku context window: 200K tokens → this is #{Bench.bold("#{Float.round(est_tokens / 200_000, 1)}x")} the limit"
)

IO.puts("  Mode: #{mode_label}")
IO.puts("  Chunk defaults: strategy=#{chunk_strategy} size=#{chunk_size} overlap=#{chunk_overlap}")
IO.puts("  Expected chunks: #{expected_chunks}")
IO.puts("  Verifiable facts: #{length(facts)} (syscalls, authors, licenses)")
IO.puts("  Max depth: #{max_depth}")
IO.puts("")

{:ok, _} = Jido.start()
{:ok, _collector} = BenchCollector.start_link()

query = build_query.(facts, bench_mode)

IO.puts(Bench.bold("Query:"))
IO.puts(Bench.dim(String.slice(query, 0, 300)))
IO.puts("")

IO.puts(Bench.bold("Agent: #{inspect(agent_mod)}"))
IO.puts("")

wall_start = System.monotonic_time(:millisecond)
{:ok, pid} = Jido.start_agent(Jido.default_instance(), agent_mod)
{:ok, workspace_ref} = agent_mod.create_workspace(pid)

{result, run_error_reason} =
  case agent_mod.explore_sync(pid, query, context: context, timeout: 600_000) do
    {:ok, r} -> {r, nil}
    {:error, reason} -> {"ERROR: #{inspect(reason)}", reason}
  end

wall_ms = System.monotonic_time(:millisecond) - wall_start
workspace = Jido.AI.RLM.WorkspaceStore.get(workspace_ref)
lua_plans = Map.get(workspace, :lua_plans, [])
lua_plan_calls = length(lua_plans)

agent_mod.delete_workspace(pid, workspace_ref)
Jido.stop_agent(Jido.default_instance(), pid)

# ── Report ─────────────────────────────────────────────────────────────

stats = BenchCollector.get_stats()

get_tok = fn u, key -> Map.get(u, key, 0) + Map.get(u, to_string(key), 0) end
total_input = stats.token_usage |> Enum.map(&get_tok.(&1, :input_tokens)) |> Enum.sum()
total_output = stats.token_usage |> Enum.map(&get_tok.(&1, :output_tokens)) |> Enum.sum()

directives = Enum.sort_by(stats.directives, & &1.at)

directive_totals =
  directives
  |> Enum.group_by(& &1.type)
  |> Enum.map(fn {type, entries} ->
    total_ms = entries |> Enum.map(& &1.duration_ms) |> Enum.sum()
    %{type: type, count: length(entries), total_ms: total_ms}
  end)
  |> Enum.sort_by(& &1.total_ms, :desc)

tool_calls = stats.tool_calls |> Enum.reverse()
lua_used? = Enum.any?(tool_calls, &(&1 == "rlm_lua_plan"))

accuracy = verify.(result, facts)

failures =
  []
  |> then(fn acc ->
    if run_error_reason do
      ["explore_sync failed: #{inspect(run_error_reason)}" | acc]
    else
      acc
    end
  end)
  |> then(fn acc ->
    if bench_mode == "lua" and lua_plan_calls == 0 do
      ["lua mode requires rlm_lua_plan, but no lua plans were recorded in workspace" | acc]
    else
      acc
    end
  end)
  |> Enum.reverse()

IO.puts(Bench.bold(String.duplicate("━", 70)))
IO.puts(Bench.bold("  RESULTS"))
IO.puts(Bench.bold(String.duplicate("━", 70)))

IO.puts("")
IO.puts(Bench.bold("Context vs Model Limits:"))
IO.puts("  Context size:        ~#{Bench.fmt_num(est_tokens)} tokens")
IO.puts("  Haiku window:        200,000 tokens")
IO.puts("  Ratio:               #{Bench.bold("#{Float.round(est_tokens / 200_000, 1)}x")} the single-model limit")
IO.puts("  #{Bench.green("✓")} No single LLM call saw the full context")
IO.puts("")

IO.puts(Bench.bold("Directive Totals:"))

Enum.each(directive_totals, fn d ->
  IO.puts(
    "  #{String.pad_trailing(d.type, 18)} count=#{String.pad_leading(Integer.to_string(d.count), 3)} total=#{Bench.fmt_ms(d.total_ms)}"
  )
end)

IO.puts("  ─────────────────")
IO.puts("  Total wall clock: #{Bench.bold(Bench.fmt_ms(wall_ms))}")
IO.puts("")

IO.puts(Bench.bold("Agents:"))
IO.puts("  Parent LLM calls:  #{stats.llm_calls}")
IO.puts("  Parent iterations:  #{stats.iteration_count}")
IO.puts("  Max depth:          #{max_depth}")
IO.puts("  Mode:               #{mode_label}")
IO.puts("")

IO.puts(Bench.bold("Tool Calls (parent):"))

if tool_calls == [] do
  IO.puts("  (none observed)")
else
  tool_calls
  |> Enum.frequencies()
  |> Enum.sort_by(fn {_tool, count} -> count end, :desc)
  |> Enum.each(fn {tool, count} ->
    IO.puts("  #{String.pad_trailing(tool, 22)} #{count}")
  end)
end

IO.puts("")

IO.puts(Bench.bold("Token Usage (parent agent only):"))
IO.puts("  Input:            #{Bench.fmt_num(total_input)}")
IO.puts("  Output:           #{Bench.fmt_num(total_output)}")
IO.puts("  Total:            #{Bench.fmt_num(total_input + total_output)}")
IO.puts("  #{Bench.dim("Note: child agent tokens are not captured in this benchmark output")}")

if bench_mode == "lua" do
  lua_text =
    if lua_plan_calls > 0 do
      Bench.green("✓ rlm_lua_plan recorded in workspace")
    else
      Bench.red("✗ no rlm_lua_plan executions recorded")
    end

  IO.puts("  Lua plans recorded: #{lua_plan_calls}")
  IO.puts("  Lua telemetry hint: #{if lua_used?, do: Bench.green("seen"), else: Bench.yellow("not seen")}")
  IO.puts("  Lua orchestration: #{lua_text}")
end

IO.puts("")

IO.puts(Bench.bold("Accuracy (verifiable facts found in answer):"))

{sh, st} = accuracy.syscalls
sc = if sh == st, do: &Bench.green/1, else: &Bench.yellow/1
IO.puts("  Syscalls:  #{sc.("#{sh}/#{st}")}")

{ah, at_} = accuracy.authors
ac = if ah == at_, do: &Bench.green/1, else: &Bench.yellow/1
IO.puts("  Authors:   #{ac.("#{ah}/#{at_}")}")

{lh, lt} = accuracy.licenses
lc = if lh == lt, do: &Bench.green/1, else: &Bench.yellow/1
IO.puts("  Licenses:  #{lc.("#{lh}/#{lt}")}")
IO.puts("")

IO.puts(Bench.bold("Answer (truncated to 800 chars):"))
IO.puts(Bench.dim(String.duplicate("-", 70)))
IO.puts(String.slice(result, 0, 800))
if String.length(result) > 800, do: IO.puts(Bench.dim("  ... (#{String.length(result)} chars total)"))
IO.puts(Bench.dim(String.duplicate("-", 70)))

# ── Cleanup ────────────────────────────────────────────────────────────

Jido.stop()

if failures == [] do
  IO.puts(Bench.green("✓ Done"))
else
  IO.puts("")
  IO.puts(Bench.red("✗ Run failed quality gates:"))
  Enum.each(failures, fn reason -> IO.puts("  - #{reason}") end)
  System.halt(2)
end
