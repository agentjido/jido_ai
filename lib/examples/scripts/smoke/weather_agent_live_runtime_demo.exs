Code.require_file(Path.expand("../shared/bootstrap.exs", __DIR__))

alias Jido.AI.Examples.Scripts.Bootstrap
alias Jido.AI.Examples.WeatherAgent

Bootstrap.init!()
Bootstrap.print_banner("Weather Agent Live Runtime Smoke Demo")

{:ok, _} = Jido.start()
{:ok, pid} = Jido.start_agent(Jido.default_instance(), WeatherAgent)

{:ok, conditions} = WeatherAgent.get_conditions(pid, "Denver", timeout: 120_000)
{:ok, umbrella} = WeatherAgent.need_umbrella?(pid, "Seattle", timeout: 120_000)

umbrella_downcased = String.downcase(umbrella)

umbrella_guidance? =
  Enum.any?(["umbrella", "rain jacket", "raincoat", "rain", "precip"], fn term ->
    String.contains?(umbrella_downcased, term)
  end)

Bootstrap.assert!(
  is_binary(conditions) and String.length(conditions) > 40,
  "get_conditions returned insufficient content."
)

Bootstrap.assert!(is_binary(umbrella) and String.length(umbrella) > 40, "need_umbrella? returned insufficient content.")

Bootstrap.assert!(
  umbrella_guidance?,
  "Umbrella response missing umbrella guidance."
)

IO.puts("✓ get_conditions returned live weather guidance")
IO.puts("✓ need_umbrella? returned practical umbrella advice")

Jido.stop_agent(Jido.default_instance(), pid)
Jido.stop()
