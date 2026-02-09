# RLM Agent Demo Script
# Run with: mix run scripts/test_rlm_agent.exs
#
# Requires valid LLM API keys configured.

Logger.configure(level: :debug)

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

# Track timing
start_time = System.monotonic_time(:millisecond)

# Attach comprehensive telemetry for RLM debugging
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
  "rlm-debug-trace",
  trace_events,
  fn event, measurements, metadata, _config ->
    ts = DateTime.utc_now() |> Calendar.strftime("%H:%M:%S.%f") |> String.slice(0, 12)
    prefix = C.dim("[#{ts}]")

    case event do
      # --- Agent CMD lifecycle ---
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

      # --- Signal lifecycle ---
      [:jido, :agent_server, :signal, :start] ->
        signal_type = metadata[:signal_type] || "unknown"

        case signal_type do
          "react.llm.delta" ->
            if delta = get_in(metadata, [:signal, :data, :delta]) do
              IO.write(delta)
            end

          "react.tool.result" ->
            tool_name = get_in(metadata, [:signal, :data, :tool_name]) || "?"
            result = get_in(metadata, [:signal, :data, :result])
            result_preview = result |> inspect() |> String.slice(0, 200)
            IO.puts("\n#{prefix}   #{C.yellow("← Tool Result")} #{C.bold(tool_name)}: #{C.dim(result_preview)}")

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

      # --- Directive lifecycle ---
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

      # --- Strategy lifecycle ---
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

      # --- ReAct machine events ---
      [:jido, :ai, :react, :start] ->
        IO.puts("#{prefix} #{C.bold(C.cyan("🔍 RLM EXPLORATION STARTED"))}")

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
        IO.puts("\n#{prefix} #{C.bold(color.("🏁 EXPLORATION COMPLETE"))}" <>
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

alias Jido.AI.Examples.NeedleHaystackAgent

# Start the default Jido instance
{:ok, _} = Jido.start()
IO.puts(C.green("✓ Jido.start() succeeded"))

# Generate a large test context with a hidden needle at a random line
needle_line = Enum.random(1..10_000)
magic_number = Enum.random(100_000..9_999_999)

IO.puts(C.bold(C.yellow("🎯 Needle planted at line #{needle_line}, magic number = #{magic_number}")))

lines =
  for i <- 1..10_000 do
    if i == needle_line do
      "Line #{i}: The secret magic number is #{magic_number}. Remember this."
    else
      "Line #{i}: #{:crypto.strong_rand_bytes(40) |> Base.encode64()}"
    end
  end

context = Enum.join(lines, "\n")

IO.puts("Context size: #{byte_size(context)} bytes (#{length(lines)} lines)")
IO.puts(C.bold("Starting RLM exploration...\n"))

# Start agent via Jido supervisor
{:ok, pid} = Jido.start_agent(Jido.default_instance(), NeedleHaystackAgent)
IO.puts(C.green("✓ Agent started: #{inspect(pid)}"))
IO.puts("")

case NeedleHaystackAgent.explore_sync(pid, "Find the magic number hidden in this text",
       context: context,
       timeout: 300_000
     ) do
  {:ok, result} ->
    elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts(C.bold(C.green("RESULT")))
    IO.puts(String.duplicate("=", 60))
    IO.puts(result)
    IO.puts(String.duplicate("=", 60))
    IO.puts(C.dim("Total wall time: #{elapsed}ms"))

  {:error, reason} ->
    elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("\n" <> C.red("Error: #{inspect(reason)}"))
    IO.puts(C.dim("Total wall time: #{elapsed}ms"))
end

Jido.stop_agent(Jido.default_instance(), pid)
IO.puts(C.green("✓ Agent stopped"))
Jido.stop()
IO.puts(C.green("✓ Jido stopped"))
