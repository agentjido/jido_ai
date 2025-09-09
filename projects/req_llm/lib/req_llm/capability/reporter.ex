defmodule ReqLLM.Capability.Reporter do
  @moduledoc """
  Capability verification reporter for ReqLLM without ExUnit dependencies.

  Provides clean output for model testing with multiple modes:
  - `:pretty` - Default CLI formatter with capability info and colored icons
  - `:json` - JSON output for CI integration
  - `:debug` - Pretty with detailed error output
  """

  @doc """
  Dispatches test results to the appropriate output format.

  ## Parameters

    * `results` - List of ReqLLM.Capability.Result structs
    * `opts` - Keyword list with :format option (:pretty, :json, or :debug)

  ## Examples

      iex> results = [%ReqLLM.Capability.Result{model: "gpt-4", capability: "generate_text", status: :passed, latency_ms: 1200}]
      iex> ReqLLM.Capability.Reporter.dispatch(results, format: :pretty)
      :ok

  """
  @spec dispatch([ReqLLM.Capability.Result.t()], keyword()) :: :ok
  def dispatch(results, opts \\ []) do
    format = Keyword.get(opts, :format, :pretty)

    case format do
      :json -> output_json(results)
      :debug -> output_debug(results)
      :pretty -> output_pretty(results)
      _ -> output_pretty(results)
    end
  end

  @doc """
  Outputs results in JSON format, one result per line.

  Each result is encoded as a separate JSON object for streaming consumption.
  """
  @spec output_json([ReqLLM.Capability.Result.t()]) :: :ok
  def output_json(results) do
    results
    |> Enum.reverse()
    |> Enum.each(&(Jason.encode!(&1) |> IO.puts()))
  end

  @doc """
  Outputs results in pretty format with colored icons and basic error info.
  """
  @spec output_pretty([ReqLLM.Capability.Result.t()]) :: :ok
  def output_pretty(results) do
    results
    |> Enum.reverse()
    |> Enum.each(&format_result(&1, false))
  end

  @doc """
  Outputs results in debug format with detailed error information.
  """
  @spec output_debug([ReqLLM.Capability.Result.t()]) :: :ok
  def output_debug(results) do
    results
    |> Enum.reverse()
    |> Enum.each(&format_result(&1, true))
  end

  defp format_result(
         %ReqLLM.Capability.Result{
           model: model,
           capability: capability,
           status: status,
           latency_ms: latency,
           details: details
         },
         debug?
       ) do
    icon = status_icon(status)
    timing = format_timing(latency)

    IO.puts("#{icon} #{model} #{capability} #{timing}")

    # Show details in debug mode for failed results
    if debug? && status == :failed && details do
      IO.puts("  Error: #{inspect(details)}")
    end
  end

  defp status_icon(:passed), do: IO.ANSI.green() <> "✓" <> IO.ANSI.reset()
  defp status_icon(:failed), do: IO.ANSI.red() <> "✗" <> IO.ANSI.reset()
  defp status_icon(_), do: "?"

  defp format_timing(ms) when ms < 1000, do: "(#{ms}ms)"
  defp format_timing(ms), do: "(#{Float.round(ms / 1000, 1)}s)"
end
