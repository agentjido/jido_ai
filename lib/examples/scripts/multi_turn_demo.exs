# Multi-Turn Conversation Demo
#
# Demonstrates that Jido.AI.Thread maintains conversation context
# across multiple calls on the same agent.
#
# Run with: mix run lib/examples/scripts/multi_turn_demo.exs
#
# Expected behavior:
# - Turn 1: Ask about Seattle weather
# - Turn 2: Ask "what about tomorrow?" - agent remembers Seattle
# - Turn 3: Ask about activities - agent still has full context

Logger.configure(level: :warning)

alias Jido.AI.Examples.WeatherAgent

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Multi-Turn Conversation Demo")
IO.puts(String.duplicate("=", 60))

# Start Jido and the agent
{:ok, _jido} = Jido.start_link(name: MultiTurnDemo.Jido)
{:ok, pid} = Jido.start_agent(MultiTurnDemo.Jido, WeatherAgent)

# Multi-turn conversation - agent maintains context across calls
turns = [
  "What's the weather like in Seattle?",
  "What about tomorrow?",
  "Any outdoor activities you'd recommend?"
]

for {message, i} <- Enum.with_index(turns, 1) do
  IO.puts("\n[Turn #{i}] #{message}")
  IO.puts(String.duplicate("-", 60))

  reply =
    case WeatherAgent.ask_sync(pid, message, timeout: 30_000) do
      {:error, {:failed, :error, reason}} = result ->
        if is_binary(reason) and String.contains?(reason, "{:busy,") do
          Process.sleep(300)
          WeatherAgent.ask_sync(pid, message, timeout: 30_000)
        else
          result
        end

      result ->
        result
    end

  case reply do
    {:ok, reply} ->
      IO.puts(reply)

    {:error, reason} ->
      IO.puts("[ERROR] #{inspect(reason)}")
      System.halt(1)
  end
end

GenServer.stop(pid)
IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Done - agent maintained context across all turns!")
IO.puts(String.duplicate("=", 60) <> "\n")
