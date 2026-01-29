defmodule Mix.Tasks.JidoAi.Agent do
  @shortdoc "Run a Jido AI agent from the command line"

  @moduledoc """
  #{@shortdoc}

  ## Usage

      # One-shot query (default)
      mix jido_ai.agent "What is 2 + 2?"

      # Interactive TUI mode
      mix jido_ai.agent --tui

      # Read from stdin (one query per line)
      echo "What is 15 * 7?" | mix jido_ai.agent --stdin

      # Use a pre-defined agent module
      mix jido_ai.agent --agent MyApp.WeatherAgent "What's the weather in Tokyo?"

      # Configure an ephemeral agent
      mix jido_ai.agent --model anthropic:claude-sonnet-4-20250514 --tools Jido.Tools.Weather "Get weather"

      # JSON output for AI agent scripting
      mix jido_ai.agent --format json --quiet "What is 2 + 2?"

  ## Options

  ### Agent Selection (choose one approach)

  **Option A: Use a pre-defined agent module**
  - `--agent` - Use an existing agent module (e.g., MyApp.WeatherAgent)
    When provided, `--model/--tools/--system/--max-iterations` are ignored.

  **Option B: Configure an ephemeral agent**
  - `--type` - Agent type/adapter: react (default). Future: cot, tot
  - `--model` - LLM model (default: anthropic:claude-haiku-4-5)
  - `--tools` - Comma-separated tool modules (default: arithmetic + weather)
  - `--system` - System prompt
  - `--max-iterations` - Max reasoning iterations (default: 10)

  ### Input Mode
  - `--stdin` - Read queries from stdin (one per line, JSON Lines output)
  - `--tui` - Launch interactive terminal UI (enter multiple queries, exit when done)

  ### Output Format
  - `--format` - Output format: text (default), json
  - `--quiet` - Suppress logs (recommended for json format)

  ### Execution
  - `--timeout` - Timeout in ms (default: 60000)

  ### Observability
  - `--trace` - Enable trace output showing signals, directives, and agent events

  ## Output Contract

  ### JSON Format (`--format json`)

  Success:
      {"ok":true,"query":"...","answer":"...","elapsed_ms":1234}

  Error:
      {"ok":false,"query":"...","error":"...","elapsed_ms":1234}

  In `--stdin` mode, outputs JSON Lines (one object per line).

  ### Exit Codes
  - `0` - All queries succeeded
  - `1` - One or more queries failed

  ## Examples

      # Basic arithmetic
      mix jido_ai.agent "Calculate 15 * 7 + 3"

      # JSON output for AI agents (Amp)
      mix jido_ai.agent --format json --quiet "What is 42 * 2?"

      # Batch processing
      cat queries.txt | mix jido_ai.agent --stdin --format json --quiet

      # Custom agent
      mix jido_ai.agent --agent Jido.AI.Examples.ReActDemoAgent "What is 100/4?"

      # Trace mode to see signals and directives
      mix jido_ai.agent --trace "Calculate 15 * 7"

  ## CLI-Compatible Agent Requirements

  Agents used with `--agent` must:
  1. Be startable via `Jido.start_agent/2`
  2. Implement `ask/2` or `ask/3` for query submission
  3. Signal completion via `strategy_snapshot.done?`
  4. Provide result via `snapshot.result` or `state.last_answer`

  Optionally implement `cli_adapter/0` to specify a custom adapter.
  """

  use Mix.Task

  alias Jido.AI.CLI.Adapter

  require Logger

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    load_dotenv()
    start_jido_instance()

    {opts, args, _invalid} =
      OptionParser.parse(argv,
        strict: [
          type: :string,
          agent: :string,
          model: :string,
          tools: :string,
          system: :string,
          max_iterations: :integer,
          stdin: :boolean,
          tui: :boolean,
          format: :string,
          quiet: :boolean,
          timeout: :integer,
          trace: :boolean
        ],
        aliases: [
          t: :type,
          a: :agent,
          m: :model,
          s: :system,
          f: :format,
          q: :quiet
        ]
      )

    config = build_config(opts)

    if config.quiet do
      Logger.configure(level: :warning)
    end

    if config.trace do
      attach_trace_handlers()
    end

    # TUI mode bypasses normal query flow
    if config.tui do
      Jido.AI.CLI.TUI.run(config)
    else
      # Resolve adapter and agent module once per invocation
      case resolve_adapter_and_agent(config) do
        {:ok, adapter, agent_module} ->
          config = Map.merge(config, %{adapter: adapter, agent_module: agent_module})
          run_queries(args, config)

        {:error, reason} ->
          output_fatal_error(config, reason)
      end
    end
  end

  defp build_config(opts) do
    %{
      type: opts[:type],
      user_agent_module: parse_module(opts[:agent]),
      model: opts[:model],
      tools: parse_tools(opts[:tools]),
      system_prompt: opts[:system],
      max_iterations: opts[:max_iterations],
      format: opts[:format] || "text",
      quiet: opts[:quiet] || false,
      timeout: opts[:timeout] || 60_000,
      stdin: opts[:stdin] || false,
      tui: opts[:tui] || false,
      trace: opts[:trace] || false
    }
  end

  defp resolve_adapter_and_agent(config) do
    case Adapter.resolve(config.type, config.user_agent_module) do
      {:ok, adapter} ->
        agent_module =
          config.user_agent_module || adapter.create_ephemeral_agent(config)

        {:ok, adapter, agent_module}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_queries(args, config) do
    if config.stdin || Enum.empty?(args) do
      run_stdin_mode(config)
    else
      query = Enum.join(args, " ")
      run_one_shot(query, config)
    end
  end

  defp run_stdin_mode(config) do
    IO.stream(:stdio, :line)
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Enum.each(fn query ->
      run_one_shot(query, config)
    end)
  end

  defp run_one_shot(query, config) do
    start_time = System.monotonic_time(:millisecond)

    case execute_query(query, config) do
      {:ok, result} ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        output_result(config, %{
          ok: true,
          query: query,
          answer: result.answer,
          elapsed_ms: elapsed
        })

      {:error, reason} ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        output_error(config, %{
          ok: false,
          query: query,
          error: format_error(reason),
          elapsed_ms: elapsed
        })
    end
  end

  defp execute_query(query, config) do
    adapter = config.adapter
    agent_module = config.agent_module

    case adapter.start_agent(JidoAi.CliJido, agent_module, config) do
      {:ok, pid} ->
        try do
          :ok = adapter.submit(pid, query, config)
          adapter.await(pid, config.timeout, config)
        after
          adapter.stop(pid)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Output helpers

  defp output_result(config, result) do
    case config.format do
      "json" ->
        IO.puts(Jason.encode!(result))

      "text" ->
        if !config.quiet, do: IO.puts("\n--- Answer ---")
        IO.puts(result.answer)
        if !config.quiet, do: IO.puts("\n(#{result.elapsed_ms}ms)")
    end
  end

  defp output_error(config, result) do
    case config.format do
      "json" ->
        IO.puts(Jason.encode!(result))

      "text" ->
        IO.puts(:stderr, "Error: #{result.error}")
    end

    System.halt(1)
  end

  defp output_fatal_error(config, reason) do
    case config.format do
      "json" ->
        IO.puts(Jason.encode!(%{ok: false, error: format_error(reason)}))

      "text" ->
        IO.puts(:stderr, "Fatal: #{format_error(reason)}")
    end

    System.halt(1)
  end

  defp format_error(:timeout), do: "Timeout waiting for agent completion"
  defp format_error(:not_found), do: "Agent process not found"
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  # Parsing helpers

  defp parse_module(nil), do: nil

  defp parse_module(module_string) do
    module = Module.concat([module_string])

    if Code.ensure_loaded?(module) do
      module
    else
      Mix.raise("Module #{module_string} not found or not loaded")
    end
  end

  defp parse_tools(nil), do: nil

  defp parse_tools(tools_string) do
    tools_string
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn mod_string ->
      module = Module.concat([mod_string])

      if !Code.ensure_loaded?(module) do
        Mix.raise("Tool module #{mod_string} not found")
      end

      module
    end)
  end

  # Setup helpers

  defp start_jido_instance do
    case Process.whereis(JidoAi.CliJido) do
      nil ->
        {:ok, _pid} = Jido.start_link(name: JidoAi.CliJido)
        :ok

      _pid ->
        :ok
    end
  end

  defp load_dotenv do
    if Code.ensure_loaded?(Dotenvy) do
      env_file = Path.join(File.cwd!(), ".env")

      if File.exists?(env_file) do
        Dotenvy.source!([env_file])
      end
    end
  end

  # Trace helpers

  @trace_events [
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
    [:jido, :agent, :strategy, :tick, :stop]
  ]

  @colors %{
    reset: "\e[0m",
    dim: "\e[2m",
    green: "\e[32m",
    yellow: "\e[33m",
    blue: "\e[34m",
    magenta: "\e[35m",
    cyan: "\e[36m",
    red: "\e[31m"
  }

  defp attach_trace_handlers do
    :telemetry.attach_many(
      "jido-ai-agent-cli-trace",
      @trace_events,
      &handle_trace_event/4,
      nil
    )
  end

  defp handle_trace_event([:jido, :agent, :cmd, :start], _measurements, metadata, _config) do
    action = metadata[:action] || "unknown"
    agent_module = metadata[:agent_module] || "?"
    IO.puts("#{@colors.green}▶ CMD START#{@colors.reset} #{agent_module} → #{inspect(action)}")
  end

  defp handle_trace_event([:jido, :agent, :cmd, :stop], measurements, metadata, _config) do
    duration_ms = div(measurements[:duration] || 0, 1_000_000)
    directive_count = metadata[:directive_count] || 0

    IO.puts(
      "#{@colors.green}✓ CMD STOP#{@colors.reset} #{@colors.dim}(#{duration_ms}ms, #{directive_count} directives)#{@colors.reset}"
    )
  end

  defp handle_trace_event([:jido, :agent, :cmd, :exception], measurements, metadata, _config) do
    duration_ms = div(measurements[:duration] || 0, 1_000_000)
    error = metadata[:error]

    IO.puts(
      "#{@colors.red}✗ CMD ERROR#{@colors.reset} #{@colors.dim}(#{duration_ms}ms)#{@colors.reset} #{inspect(error)}"
    )
  end

  defp handle_trace_event([:jido, :agent_server, :signal, :start], _measurements, metadata, _cfg) do
    signal_type = metadata[:signal_type] || "unknown"
    IO.puts("  #{@colors.cyan}→ Signal#{@colors.reset} #{signal_type}")
  end

  defp handle_trace_event([:jido, :agent_server, :signal, :stop], measurements, metadata, _cfg) do
    duration_ms = div(measurements[:duration] || 0, 1_000_000)
    signal_type = metadata[:signal_type] || "unknown"

    IO.puts("  #{@colors.cyan}← Signal#{@colors.reset} #{signal_type} #{@colors.dim}(#{duration_ms}ms)#{@colors.reset}")
  end

  defp handle_trace_event([:jido, :agent_server, :signal, :exception], _m, metadata, _config) do
    signal_type = metadata[:signal_type] || "unknown"
    error = metadata[:error]
    IO.puts("  #{@colors.red}✗ Signal ERROR#{@colors.reset} #{signal_type}: #{inspect(error)}")
  end

  defp handle_trace_event([:jido, :agent_server, :directive, :start], _m, metadata, _config) do
    directive_type = metadata[:directive_type] || "unknown"
    IO.puts("    #{@colors.yellow}⚡ Directive#{@colors.reset} #{directive_type}")
  end

  defp handle_trace_event([:jido, :agent_server, :directive, :stop], measurements, metadata, _c) do
    duration_ms = div(measurements[:duration] || 0, 1_000_000)
    directive_type = metadata[:directive_type] || "unknown"

    IO.puts(
      "    #{@colors.yellow}✓ Directive#{@colors.reset} #{directive_type} #{@colors.dim}(#{duration_ms}ms)#{@colors.reset}"
    )
  end

  defp handle_trace_event([:jido, :agent_server, :directive, :exception], _m, metadata, _config) do
    directive_type = metadata[:directive_type] || "unknown"
    error = metadata[:error]

    IO.puts("    #{@colors.red}✗ Directive ERROR#{@colors.reset} #{directive_type}: #{inspect(error)}")
  end

  defp handle_trace_event([:jido, :agent, :strategy, :cmd, :start], _m, metadata, _config) do
    strategy = metadata[:strategy] || "?"
    IO.puts("  #{@colors.magenta}▸ Strategy CMD#{@colors.reset} #{strategy}")
  end

  defp handle_trace_event([:jido, :agent, :strategy, :cmd, :stop], measurements, metadata, _c) do
    duration_ms = div(measurements[:duration] || 0, 1_000_000)
    directive_count = metadata[:directive_count] || 0

    IO.puts(
      "  #{@colors.magenta}◂ Strategy CMD#{@colors.reset} #{@colors.dim}(#{duration_ms}ms, #{directive_count} directives)#{@colors.reset}"
    )
  end

  defp handle_trace_event([:jido, :agent, :strategy, :cmd, :exception], _m, metadata, _config) do
    strategy = metadata[:strategy] || "?"
    error = metadata[:error]
    IO.puts("  #{@colors.red}✗ Strategy ERROR#{@colors.reset} #{strategy}: #{inspect(error)}")
  end

  defp handle_trace_event([:jido, :agent, :strategy, :tick, :start], _m, metadata, _config) do
    strategy = metadata[:strategy] || "?"
    IO.puts("  #{@colors.blue}⟳ Strategy TICK#{@colors.reset} #{strategy}")
  end

  defp handle_trace_event([:jido, :agent, :strategy, :tick, :stop], measurements, _metadata, _c) do
    duration_ms = div(measurements[:duration] || 0, 1_000_000)
    IO.puts("  #{@colors.blue}⟲ Strategy TICK#{@colors.reset} #{@colors.dim}(#{duration_ms}ms)#{@colors.reset}")
  end

  defp handle_trace_event(_event, _measurements, _metadata, _config) do
    :ok
  end
end
