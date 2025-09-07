defmodule ReqLLM.ExUnit.ModelVerifierFormatter do
  @moduledoc """
  Custom ExUnit formatter for ReqLLM model verification that provides clean,
  tabular output optimized for bulk model testing.

  Replaces verbose ExUnit output with concise tables showing:
  - Model and capability being tested
  - Pass/fail status with visual indicators
  - Response time metrics
  - Failure details only when needed

  ## Output Formats

  - `:pretty` - Clean tabular output with colors (default)
  - `:debug` - Same as pretty but shows all success/failure details
  - `:json` - Machine-readable JSON lines for CI integration

  """

  use GenServer
  alias ExUnit.Test
  require Logger

  defstruct mode: :pretty,
            show_all?: false,
            rows: [],
            start_at: nil,
            current_model: nil

  @impl GenServer
  def init(_opts) do
    # Get formatter options from Application env (set by CapabilityVerifier)
    formatter_opts = Application.get_env(:req_llm, :formatter_opts, mode: :pretty)

    mode =
      case Keyword.get(formatter_opts, :mode, :pretty) do
        mode when is_atom(mode) -> mode
        mode when is_binary(mode) -> String.to_atom(mode)
      end

    show_all? = mode == :debug

    {:ok,
     %__MODULE__{
       mode: mode,
       show_all?: show_all?,
       start_at: now_ms(),
       rows: []
     }}
  end

  @impl GenServer
  def handle_cast({:test_started, %Test{name: name}}, state) do
    {model, _capability} = parse_test_name(name)

    # Print model header when we start testing a new model
    if state.current_model != model do
      unless state.current_model == nil do
        print_model_summary(state.rows, state.current_model, state)
      end

      print_model_header(model)
      {:noreply, %{state | current_model: model, rows: []}}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast(
        {:test_finished, %Test{name: name, state: test_state, time: microseconds}},
        state
      ) do
    {model, capability} = parse_test_name(name)

    {status, details} = parse_test_result(test_state)

    time_ms = div(microseconds, 1000)

    row = {model, capability, status, time_ms, details}

    # For JSON mode, print immediately
    if state.mode == :json do
      print_json_row(row)
    end

    new_state = %{state | rows: [row | state.rows]}
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast({:suite_finished, _run_us, _load_us}, state) do
    # Print final model summary if we have rows
    unless Enum.empty?(state.rows) do
      print_model_summary(state.rows, state.current_model, state)
    end

    {:noreply, state}
  end

  # Ignore other ExUnit events
  @impl GenServer
  def handle_cast(_event, state), do: {:noreply, state}

  # Parse test name to extract model and capability
  # Test names are atoms like :"test anthropic:claude-3-sonnet_generate_text"
  defp parse_test_name(name) do
    name_str = Atom.to_string(name)

    # Remove "test " prefix that ExUnit adds
    clean_name = String.replace_prefix(name_str, "test ", "")

    # Split on the last underscore to separate model ID from capability
    case String.split(clean_name, "_") do
      [model_part | capability_parts] when capability_parts != [] ->
        # Handle cases where model ID contains underscores (from sanitization)
        # Look for provider:model pattern
        if String.contains?(model_part, ":") do
          capability = Enum.join(capability_parts, "_")
          {model_part, capability}
        else
          # Try to find the split point by looking for provider patterns
          parts = [model_part | capability_parts]
          {model, capability} = find_model_capability_split(parts)
          {model, capability}
        end

      [single_part] ->
        # No underscore, treat as capability only
        {"unknown_model", single_part}
    end
  end

  # Helper to find where model ends and capability begins
  defp find_model_capability_split(parts) do
    # Look for common capability names at the end
    capability_names = ["generate_text", "stream_text"]

    Enum.reduce_while(capability_names, {"unknown_model", Enum.join(parts, "_")}, fn cap_name,
                                                                                     acc ->
      if List.last(parts) == cap_name do
        model_parts = Enum.drop(parts, -1)
        model = Enum.join(model_parts, "_")
        {:halt, {model, cap_name}}
      else
        {:cont, acc}
      end
    end)
  end

  # Parse ExUnit test result
  defp parse_test_result(nil), do: {:ok, nil}

  defp parse_test_result({:failed, failures}) do
    error_msg =
      failures
      |> Enum.map(&format_failure/1)
      |> Enum.join("; ")

    {:error, error_msg}
  end

  defp format_failure({kind, reason, _stack}) do
    Exception.format(kind, reason)
  end

  defp print_model_header(model) do
    unless model == "unknown_model" do
      IO.puts("\n" <> IO.ANSI.cyan() <> "─── Verifying #{model} ───" <> IO.ANSI.reset())
    end
  end

  defp print_model_summary(rows, _model, state) when state.mode != :json do
    reversed_rows = Enum.reverse(rows)

    unless Enum.empty?(reversed_rows) do
      print_table(reversed_rows, state)
      print_summary_line(reversed_rows)
    end
  end

  defp print_model_summary(_rows, _model, _state), do: :ok

  defp print_table(rows, _state) do
    if Enum.empty?(rows) do
      :ok
    else
      # Calculate column widths
      max_model_width =
        rows |> Enum.map(fn {m, _, _, _, _} -> String.length(m) end) |> Enum.max(fn -> 5 end)

      max_cap_width =
        rows |> Enum.map(fn {_, c, _, _, _} -> String.length(c) end) |> Enum.max(fn -> 10 end)

      # Ensure minimum widths
      model_width = max(max_model_width, 5)
      cap_width = max(max_cap_width, 10)

      # Print table header
      print_table_header(model_width, cap_width)

      # Print each row
      Enum.each(rows, fn {model, capability, status, time_ms, details} ->
        print_table_row(model, capability, status, time_ms, model_width, cap_width)

        # Print failure details if needed
        if status == :error do
          print_failure_details(details)
        end
      end)

      print_table_footer(model_width, cap_width)
    end
  end

  defp print_table_header(model_width, cap_width) do
    header_line =
      "┌" <>
        String.duplicate("─", model_width + 2) <>
        "┬" <>
        String.duplicate("─", cap_width + 2) <>
        "┬─────────┬─────────┐"

    IO.puts(header_line)

    model_header = String.pad_trailing("Model", model_width)
    cap_header = String.pad_trailing("Capability", cap_width)

    data_line =
      "│ " <> model_header <> " │ " <> cap_header <> " │ Status  │ Time    │"

    IO.puts(data_line)

    separator_line =
      "├" <>
        String.duplicate("─", model_width + 2) <>
        "┼" <>
        String.duplicate("─", cap_width + 2) <>
        "┼─────────┼─────────┤"

    IO.puts(separator_line)
  end

  defp print_table_row(model, capability, status, time_ms, model_width, cap_width) do
    status_indicator =
      case status do
        :ok -> IO.ANSI.green() <> "✅ PASS" <> IO.ANSI.reset()
        :error -> IO.ANSI.red() <> "❌ FAIL" <> IO.ANSI.reset()
      end

    time_str = format_time(time_ms)

    model_cell = String.pad_trailing(model, model_width)
    cap_cell = String.pad_trailing(capability, cap_width)
    time_cell = String.pad_trailing(time_str, 7)

    row_line =
      "│ " <>
        model_cell <> " │ " <> cap_cell <> " │ " <> status_indicator <> " │ " <> time_cell <> " │"

    IO.puts(row_line)
  end

  defp print_table_footer(model_width, cap_width) do
    footer_line =
      "└" <>
        String.duplicate("─", model_width + 2) <>
        "┴" <>
        String.duplicate("─", cap_width + 2) <>
        "┴─────────┴─────────┘"

    IO.puts(footer_line)
  end

  defp print_failure_details(details) do
    if details && String.trim(details) != "" do
      formatted =
        details
        |> String.trim()
        |> String.replace("\n", "\n    ↳ ")

      IO.puts("    " <> IO.ANSI.red() <> "↳ " <> formatted <> IO.ANSI.reset())
    end
  end

  defp print_summary_line(rows) do
    passed = Enum.count(rows, fn {_, _, status, _, _} -> status == :ok end)
    failed = Enum.count(rows, fn {_, _, status, _, _} -> status == :error end)
    total = length(rows)

    summary =
      if failed == 0 do
        IO.ANSI.green() <> "✅ All #{total} capabilities passed" <> IO.ANSI.reset()
      else
        IO.ANSI.red() <>
          "❌ #{failed}/#{total} capabilities failed (#{passed} passed)" <> IO.ANSI.reset()
      end

    IO.puts("\n" <> summary)
  end

  defp print_json_row({model, capability, status, time_ms, details}) do
    json_obj = %{
      model: model,
      capability: capability,
      status: status,
      latency_ms: time_ms
    }

    json_obj =
      if status == :error and details do
        Map.put(json_obj, :error, details)
      else
        json_obj
      end

    IO.puts(Jason.encode!(json_obj))
  end

  defp format_time(ms) when ms < 1000, do: "#{ms}ms"
  defp format_time(ms), do: "#{Float.round(ms / 1000, 2)}s"

  defp now_ms do
    System.monotonic_time(:millisecond)
  end
end
