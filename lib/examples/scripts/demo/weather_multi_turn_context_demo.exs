Code.require_file(Path.expand("../shared/bootstrap.exs", __DIR__))

alias Jido.AI.Examples.Scripts.Bootstrap
alias Jido.AI.Examples.WeatherAgent

defmodule WeatherMultiTurnContextDemo.Helpers do
  @max_attempts 6
  @base_backoff_ms 200
  @max_backoff_ms 2_000

  def ask_with_retry(pid, message, timeout \\ 60_000) do
    do_ask_with_retry(pid, message, timeout, 1)
  end

  defp do_ask_with_retry(pid, message, timeout, attempt) do
    result = WeatherAgent.ask_sync(pid, message, timeout: timeout)

    if busy_error?(result) and attempt < @max_attempts do
      backoff_ms = backoff_ms(attempt)

      IO.puts("Agent busy; retrying in #{backoff_ms}ms (attempt #{attempt + 1}/#{@max_attempts})")

      Process.sleep(backoff_ms)
      do_ask_with_retry(pid, message, timeout, attempt + 1)
    else
      result
    end
  end

  defp busy_error?({:error, {:rejected, :busy, _message}}), do: true
  defp busy_error?({:error, {:failed, :busy, _reason}}), do: true

  defp busy_error?({:error, {:failed, :error, reason}})
       when is_binary(reason),
       do: String.contains?(reason, "{:busy,")

  defp busy_error?(_), do: false

  defp backoff_ms(attempt) when is_integer(attempt) and attempt > 0 do
    trunc(@base_backoff_ms * :math.pow(2, attempt - 1))
    |> min(@max_backoff_ms)
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
