defmodule ReqLLM.Capability.Formatter do
  @moduledoc """
  ExUnit formatter for ReqLLM capability verification.

  Provides clean output for model testing with multiple modes:
  - `:pretty` - Default CLI formatter with capability info
  - `:json` - JSON output for CI integration
  - `:debug` - Pretty with detailed output
  """

  use GenServer
  alias ExUnit.CLIFormatter, as: Default

  @impl GenServer
  def init(opts) do
    mode = Application.get_env(:req_llm, :formatter_opts, [])[:mode] || :pretty
    {:ok, delegate_state} = Default.init(opts)
    {:ok, %{delegate: delegate_state, mode: mode, results: []}}
  end

  @impl GenServer
  def handle_cast({:test_finished, test}, state) do
    Default.handle_cast({:test_finished, test}, state.delegate)

    result = extract_test_result(test)
    results = [result | state.results]

    {:noreply, %{state | results: results}}
  end

  @impl GenServer
  def handle_cast({:suite_finished, run_us, load_us}, state) do
    Default.handle_cast({:suite_finished, run_us, load_us}, state.delegate)
    dump_results_if_needed(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(event, state) do
    Default.handle_cast(event, state.delegate)
    {:noreply, state}
  end

  defp extract_test_result(test) do
    {model, capability} = parse_test_name(test.name)

    %{
      model: model,
      capability: capability,
      status: if(test.state == nil, do: :passed, else: :failed),
      latency_ms: div(test.time, 1000),
      error: format_error(test.state)
    }
  end

  defp parse_test_name(name) do
    name_str = name |> to_string() |> String.replace_prefix("test ", "")

    case String.split(name_str, "_", parts: 2) do
      [model, capability] -> {model, capability}
      [single] -> {"unknown", single}
    end
  end

  defp format_error(nil), do: nil

  defp format_error({:failed, failures}) do
    failures
    |> Enum.map(fn {kind, reason, _stack} -> Exception.format(kind, reason) end)
    |> Enum.join("; ")
  end

  defp dump_results_if_needed(%{mode: :json, results: results}) do
    results |> Enum.reverse() |> Enum.each(&(Jason.encode!(&1) |> IO.puts()))
  end

  defp dump_results_if_needed(_), do: :ok
end
