defmodule Jido.AI.CLI.TUI do
  @moduledoc """
  Minimal interactive terminal UI for `mix jido_ai.agent --tui`.

  The Mix task supports `--tui`, but historically referenced this module without
  providing an implementation. This module keeps the experience simple and
  dependency-free: it runs a REPL-style loop and executes queries using the
  configured CLI adapter.
  """

  alias Jido.AI.CLI.Adapter

  require Logger

  @quit_commands [":q", ":quit", ":exit", "q", "quit", "exit"]

  @spec run(map()) :: :ok | no_return()
  def run(config) when is_map(config) do
    # TUI is inherently interactive; force text output.
    config = Map.put(config, :format, "text")

    case resolve_adapter_and_agent(config) do
      {:ok, adapter, agent_module} ->
        config = Map.merge(config, %{adapter: adapter, agent_module: agent_module})
        print_banner(config)
        loop(config)

      {:error, reason} ->
        fatal(reason)
    end
  end

  defp print_banner(config) do
    unless config[:quiet] do
      IO.puts("""

      Jido AI Agent (TUI)

      - Type your prompt and press Enter
      - Type #{Enum.join(@quit_commands, ", ")} to quit
      """)
    end
  end

  defp loop(config) do
    case IO.gets("> ") do
      nil ->
        :ok

      line ->
        line
        |> String.trim()
        |> handle_input(config)

        loop(config)
    end
  end

  defp handle_input("", _config), do: :ok

  defp handle_input(input, config) do
    if input in @quit_commands do
      :ok
      |> then(fn _ -> System.halt(0) end)
    else
      run_one_shot(input, config)
    end
  end

  defp run_one_shot(query, config) do
    start_time = System.monotonic_time(:millisecond)

    case execute_query(query, config) do
      {:ok, result} ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        output_answer(result.answer, elapsed, result.meta, config)
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{format_error(reason)}")
        :ok
    end
  end

  defp output_answer(answer, elapsed_ms, meta, config) do
    IO.puts("")
    IO.puts(answer)

    unless config[:quiet] do
      stats =
        meta
        |> Map.new()
        |> Map.put_new(:elapsed_ms, elapsed_ms)
        |> format_stats()

      IO.puts("")
      IO.puts(stats)
      IO.puts("")
    end
  end

  defp execute_query(query, config) do
    adapter = config.adapter
    agent_module = config.agent_module

    case adapter.start_agent(JidoAi.CliJido, agent_module, config) do
      {:ok, pid} ->
        try do
          {:ok, _request} = adapter.submit(pid, query, config)
          adapter.await(pid, config.timeout, config)
        after
          adapter.stop(pid)
        end

      {:error, reason} ->
        {:error, reason}
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

  defp format_stats(%{elapsed_ms: elapsed_ms} = meta) do
    parts = ["(#{elapsed_ms}ms"]

    parts =
      case Map.get(meta, :iterations) do
        n when is_integer(n) and n > 0 -> parts ++ ["#{n} iterations"]
        _ -> parts
      end

    parts =
      case Map.get(meta, :usage) do
        %{input_tokens: input, output_tokens: output} when input > 0 or output > 0 ->
          total = input + output

          parts ++
            [
              "#{format_number(total)} tokens (#{format_number(input)} in / #{format_number(output)} out)"
            ]

        _ ->
          parts
      end

    Enum.join(parts, ", ") <> ")"
  end

  defp format_number(n) when is_integer(n) and n >= 1000, do: "#{Float.round(n / 1000, 1)}k"
  defp format_number(n) when is_integer(n), do: "#{n}"
  defp format_number(n), do: to_string(n)

  defp format_error(:timeout), do: "Timeout waiting for agent completion"
  defp format_error(:not_found), do: "Agent process not found"
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp fatal(reason) do
    IO.puts(:stderr, "Fatal: #{format_error(reason)}")
    System.halt(1)
  end
end
