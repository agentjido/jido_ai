# Test script for WeatherAgent
# Run with: mix run scripts/test_weather_agent.exs
#
# This demonstrates:
# 1. Using Jido.start/0 for easy script startup
# 2. The WeatherAgent convenience methods
# 3. Streaming token display via telemetry

Logger.configure(level: :warning)

# Colors for terminal output
defmodule Colors do
  def cyan(text), do: "\e[36m#{text}\e[0m"
  def green(text), do: "\e[32m#{text}\e[0m"
  def dim(text), do: "\e[2m#{text}\e[0m"
end

# Attach telemetry handler to show streaming tokens
:telemetry.attach(
  "weather-agent-stream",
  [:jido, :agent_server, :signal, :start],
  fn _event, _measurements, metadata, _config ->
    case metadata do
      %{signal_type: "reqllm.partial"} ->
        # Extract delta from signal data if available
        if delta = get_in(metadata, [:signal, :data, :delta]) do
          IO.write(delta)
        end
      _ ->
        :ok
    end
  end,
  nil
)

# Start the default Jido instance
{:ok, _} = Jido.start()
IO.puts(Colors.green("✓ Jido.start() succeeded"))

alias Jido.AI.Examples.WeatherAgent

# Start the weather agent
IO.puts("Starting WeatherAgent...")
{:ok, pid} = Jido.start_agent(Jido.default_instance(), WeatherAgent)
IO.puts(Colors.green("✓ Agent started: #{inspect(pid)}"))

# Test get_conditions with streaming display
IO.puts("\n" <> Colors.cyan("--- Testing get_conditions/3 for Denver ---"))
IO.puts(Colors.dim("(Streaming response below)"))
IO.puts("")

case WeatherAgent.get_conditions(pid, "Denver", timeout: 120_000) do
  {:ok, _conditions} ->
    IO.puts("\n" <> Colors.green("✓ get_conditions completed"))
  {:error, reason} ->
    IO.puts("\n✗ get_conditions failed: #{inspect(reason)}")
end

# Test need_umbrella? with streaming display
IO.puts("\n" <> Colors.cyan("--- Testing need_umbrella?/3 for Seattle ---"))
IO.puts(Colors.dim("(Streaming response below)"))
IO.puts("")

case WeatherAgent.need_umbrella?(pid, "Seattle", timeout: 120_000) do
  {:ok, _advice} ->
    IO.puts("\n" <> Colors.green("✓ need_umbrella? completed"))
  {:error, reason} ->
    IO.puts("\n✗ need_umbrella? failed: #{inspect(reason)}")
end

IO.puts("\n" <> Colors.green("--- All tests complete ---"))
Jido.stop_agent(Jido.default_instance(), pid)
IO.puts(Colors.green("✓ Agent stopped"))
Jido.stop()
IO.puts(Colors.green("✓ Jido stopped"))
