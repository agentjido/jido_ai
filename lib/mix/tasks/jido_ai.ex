defmodule Mix.Tasks.JidoAi do
  @shortdoc "Run Jido AI from the command line (one-shot or stdin)"

  @moduledoc """
  Unified Jido AI CLI task.

  Provide a query for one-shot execution, or `--stdin` for batch mode.

  ## Quick Start

      # One-shot query
      mix jido_ai "Calculate 15 * 7 + 3"

      # Batch mode from stdin
      cat queries.txt | mix jido_ai --stdin --format json --quiet

  ## Modes

  - One-shot mode: query args provided
  - Stdin mode: `--stdin`

  ## Options

  ### Agent Configuration
      --agent MODULE       Use existing agent module (ignores --model/--tools/--system)
      --type TYPE          Agent type: react (default), cot, tot, got, trm, adaptive
      --model MODEL        LLM model (default: anthropic:claude-haiku-4-5)
      --tools MODULES      Comma-separated tool modules
      --system PROMPT      System prompt
      --max-iterations N   Max reasoning iterations (default: 10)

  ### Input Mode
      --stdin              Read queries from stdin (one per line)

  ### Output Format (one-shot/stdin)
      --format FORMAT      text (default) | json
      --quiet              Suppress logs (use with --format json)

  ### Execution
      --timeout MS         Timeout in ms (default: 60000)
      --trace              Show signals, directives, and AI lifecycle events

  ## Examples

      # One-shot with a custom agent
      mix jido_ai --agent MyApp.WeatherAgent "Will it rain in Seattle?"

      # One-shot with specific model/tools
      mix jido_ai --model openai:gpt-4o --tools Jido.Tools.Arithmetic "15 * 23"

      # One-shot with tracing
      mix jido_ai --trace "Will it rain in Seattle today?"
  """

  use Mix.Task

  alias Jido.AI.CLI.Adapter

  require Logger

  @impl Mix.Task
  def run(argv) do
    Mix.Task.rerun("app.start")
    load_dotenv()

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

    cond do
      config.stdin ->
        start_jido_instance(JidoAi.CliJido)
        run_non_interactive(args, config)

      Enum.empty?(args) ->
        output_fatal_error(
          config,
          "No query provided. Pass a prompt (mix jido_ai \"<prompt>\") or use --stdin for batch mode."
        )

      true ->
        start_jido_instance(JidoAi.CliJido)
        run_non_interactive(args, config)
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
      trace: opts[:trace] || false
    }
  end

  defp run_non_interactive(args, config) do
    case resolve_adapter_and_agent(config) do
      {:ok, adapter, agent_module} ->
        config = Map.merge(config, %{adapter: adapter, agent_module: agent_module})

        if config.stdin do
          run_stdin_mode(config)
        else
          query = Enum.join(args, " ")
          run_one_shot(query, config)
        end

      {:error, reason} ->
        output_fatal_error(config, reason)
    end
  end

  defp resolve_adapter_and_agent(config) do
    case Adapter.resolve(config.type, config.user_agent_module) do
      {:ok, adapter} ->
        agent_module = config.user_agent_module || adapter.create_ephemeral_agent(config)
        {:ok, adapter, agent_module}

      {:error, reason} ->
        {:error, reason}
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
          elapsed_ms: elapsed,
          usage: Map.get(result.meta, :usage),
          iterations: Map.get(result.meta, :iterations),
          model: Map.get(result.meta, :model)
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
          case adapter.submit(pid, query, config) do
            {:ok, _request} -> adapter.await(pid, config.timeout, config)
            :ok -> adapter.await(pid, config.timeout, config)
            {:error, reason} -> {:error, reason}
          end
        after
          adapter.stop(pid)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp output_result(config, result) do
    case config.format do
      "json" ->
        IO.puts(Jason.encode!(result))

      "text" ->
        if !config.quiet, do: IO.puts("\n--- Answer ---")
        IO.puts(result.answer)
        if !config.quiet, do: IO.puts("\n#{format_stats(result)}")
    end
  end

  defp format_stats(result) do
    parts = ["(#{result.elapsed_ms}ms"]

    parts =
      if result[:iterations] && result[:iterations] > 0 do
        parts ++ ["#{result[:iterations]} iterations"]
      else
        parts
      end

    parts =
      case result[:usage] do
        %{input_tokens: input, output_tokens: output} when input > 0 or output > 0 ->
          total = input + output
          parts ++ ["#{format_number(total)} tokens (#{format_number(input)} in / #{format_number(output)} out)"]

        _ ->
          parts
      end

    Enum.join(parts, ", ") <> ")"
  end

  defp format_number(n) when n >= 1000, do: "#{Float.round(n / 1000, 1)}k"
  defp format_number(n), do: "#{n}"

  @spec output_error(map(), map()) :: no_return()
  defp output_error(config, result) do
    case config.format do
      "json" ->
        IO.puts(Jason.encode!(result))

      "text" ->
        IO.puts(:stderr, "Error: #{result.error}")
    end

    System.halt(1)
  end

  @spec output_fatal_error(map(), term()) :: no_return()
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

  defp parse_module(nil), do: nil

  defp parse_module(module_string) do
    module = Module.concat([module_string])

    if Code.ensure_loaded?(module) do
      module
    else
      raise "Module #{module_string} not found or not loaded"
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
        raise "Tool module #{mod_string} not found"
      end

      module
    end)
  end

  defp start_jido_instance(instance_name) do
    case Process.whereis(instance_name) do
      nil ->
        {:ok, _pid} = Jido.start_link(name: instance_name)
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
    [:jido, :agent, :strategy, :tick, :stop],
    [:jido, :ai, :request, :start],
    [:jido, :ai, :request, :complete],
    [:jido, :ai, :request, :failed],
    [:jido, :ai, :request, :rejected],
    [:jido, :ai, :request, :cancelled],
    [:jido, :ai, :llm, :start],
    [:jido, :ai, :llm, :delta],
    [:jido, :ai, :llm, :complete],
    [:jido, :ai, :llm, :error],
    [:jido, :ai, :tool, :start],
    [:jido, :ai, :tool, :retry],
    [:jido, :ai, :tool, :complete],
    [:jido, :ai, :tool, :error],
    [:jido, :ai, :tool, :timeout]
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
    :telemetry.attach_many("jido-ai-cli-trace", @trace_events, &handle_trace_event/4, nil)
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

  defp handle_trace_event([:jido, :ai, :request, event], measurements, metadata, _config)
       when event in [:start, :complete, :failed, :rejected, :cancelled] do
    req = metadata[:request_id] || "?"
    duration = measurements[:duration_ms] || 0
    reason = metadata[:termination_reason] || metadata[:error_type]

    IO.puts(
      "  #{@colors.blue}REQ #{String.upcase(to_string(event))}#{@colors.reset} id=#{req} #{@colors.dim}(#{duration}ms#{if(reason, do: ", #{reason}", else: "")})#{@colors.reset}"
    )
  end

  defp handle_trace_event([:jido, :ai, :llm, event], measurements, metadata, _config)
       when event in [:start, :delta, :complete, :error] do
    call_id = metadata[:llm_call_id] || "?"
    model = metadata[:model] || "?"
    duration = measurements[:duration_ms] || 0

    IO.puts(
      "    #{@colors.cyan}LLM #{String.upcase(to_string(event))}#{@colors.reset} call=#{call_id} model=#{model} #{@colors.dim}(#{duration}ms)#{@colors.reset}"
    )
  end

  defp handle_trace_event([:jido, :ai, :tool, event], measurements, metadata, _config)
       when event in [:start, :retry, :complete, :error, :timeout] do
    tool = metadata[:tool_name] || "?"
    call_id = metadata[:tool_call_id] || "?"
    duration = measurements[:duration_ms] || 0
    retries = measurements[:retry_count] || 0

    IO.puts(
      "    #{@colors.yellow}TOOL #{String.upcase(to_string(event))}#{@colors.reset} #{tool} call=#{call_id} #{@colors.dim}(#{duration}ms, retries=#{retries})#{@colors.reset}"
    )
  end

  defp handle_trace_event(_event, _measurements, _metadata, _config), do: :ok
end
