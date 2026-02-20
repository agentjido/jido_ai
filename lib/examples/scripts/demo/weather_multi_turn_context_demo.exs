Code.require_file(Path.expand("../shared/bootstrap.exs", __DIR__))

alias Jido.AI.Examples.Scripts.Bootstrap
alias Jido.AI.Examples.WeatherAgent

defmodule WeatherMultiTurnContextDemo.Helpers do
  def ask_with_retry(pid, message, timeout \\ 60_000) do
    case WeatherAgent.ask_sync(pid, message, timeout: timeout) do
      {:error, {:failed, :error, reason}} = result ->
        if is_binary(reason) and String.contains?(reason, "{:busy,") do
          Process.sleep(300)
          WeatherAgent.ask_sync(pid, message, timeout: timeout)
        else
          result
        end

      result ->
        result
    end
  end
end

Bootstrap.init!()
Bootstrap.print_banner("Weather Multi-Turn Context Demo")
Bootstrap.start_named_jido!(WeatherMultiTurnContextDemo.Jido)

{:ok, pid} = Jido.start_agent(WeatherMultiTurnContextDemo.Jido, WeatherAgent)

city = "Seattle"

turns = [
  "I'm in #{city}. Give tomorrow's weather in one short paragraph and explicitly mention #{city}.",
  "Context carryover: city=#{city}. Should I bring an umbrella? Mention #{city} explicitly.",
  "Context carryover: city=#{city}. Suggest one outdoor and one indoor activity. Mention #{city} explicitly."
]

responses =
  for {message, index} <- Enum.with_index(turns, 1) do
    IO.puts("\n[Turn #{index}] #{message}")
    IO.puts(String.duplicate("-", 72))

    case WeatherMultiTurnContextDemo.Helpers.ask_with_retry(pid, message, 90_000) do
      {:ok, reply} when is_binary(reply) ->
        IO.puts(reply)
        reply

      {:error, reason} ->
        raise "Multi-turn demo failed on turn #{index}: #{inspect(reason)}"
    end
  end

[first_reply, second_reply, third_reply] = responses
city_downcased = String.downcase(city)

Bootstrap.assert!(
  String.contains?(String.downcase(first_reply), city_downcased),
  "Turn 1 did not anchor to city context."
)

Bootstrap.assert!(
  String.contains?(String.downcase(second_reply), city_downcased),
  "Turn 2 lost carried city context."
)

Bootstrap.assert!(
  String.contains?(String.downcase(second_reply), "umbrella"),
  "Turn 2 did not address umbrella guidance."
)

Bootstrap.assert!(
  String.contains?(String.downcase(third_reply), city_downcased),
  "Turn 3 lost carried city context."
)

Bootstrap.assert!(
  String.contains?(String.downcase(third_reply), "outdoor"),
  "Turn 3 missing outdoor activity suggestion."
)

Bootstrap.assert!(
  String.contains?(String.downcase(third_reply), "indoor"),
  "Turn 3 missing indoor activity suggestion."
)

GenServer.stop(pid)
IO.puts("\n✓ Multi-turn context demo passed semantic checks")
