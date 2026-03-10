Code.require_file(Path.expand("../shared/bootstrap.exs", __DIR__))

alias Jido.AI.Examples.Scripts.Bootstrap
alias Jido.AI.Examples.Paths
alias Jido.AI.Examples.SkillsDemoAgent
alias Jido.AI.Skill.{Loader, Registry}

Bootstrap.init!(required_env: ["ANTHROPIC_API_KEY"])
Bootstrap.print_banner("Skills Multi-Agent Orchestration Demo")

skill_root = Paths.repo_path("priv/skills")
unit_converter_skill = Path.join(skill_root, "unit-converter/SKILL.md")

Bootstrap.assert!(File.exists?(unit_converter_skill), "Missing #{unit_converter_skill}")
{:ok, _spec} = Loader.load(unit_converter_skill)

:ok = Registry.ensure_started()
{:ok, _count} = Registry.load_from_paths([skill_root])

Bootstrap.start_named_jido!(SkillsMultiAgentOrchestrationDemo.Jido)
{:ok, pid} = Jido.start_agent(SkillsMultiAgentOrchestrationDemo.Jido, SkillsDemoAgent)

questions = [
  {"Arithmetic", "What is 42 * 17 + 100?"},
  {"Conversion", "Convert 98.6 degrees Fahrenheit to Celsius"},
  {"Combined", "If I run 5 kilometers, how many miles is that? Then estimate calories at 100 calories/mile."}
]

responses =
  for {label, question} <- questions do
    IO.puts("\n[#{label}] #{question}")
    IO.puts(String.duplicate("-", 72))

    case SkillsDemoAgent.ask_sync(pid, question, timeout: 90_000) do
      {:ok, reply} when is_binary(reply) ->
        IO.puts(reply)
        reply

      {:error, reason} ->
        raise "Skills orchestration demo failed for #{label}: #{inspect(reason)}"
    end
  end

[first_reply, second_reply, third_reply] = responses

Bootstrap.assert!(String.contains?(first_reply, "814"), "Arithmetic response missing expected result 814.")
Bootstrap.assert!(String.contains?(second_reply, "37"), "Conversion response missing expected Celsius value.")

Bootstrap.assert!(
  String.contains?(String.downcase(third_reply), "mile") and
    (String.contains?(third_reply, "3.1") or String.contains?(third_reply, "3.11")),
  "Combined response missing expected kilometer-to-mile conversion details."
)

GenServer.stop(pid)
IO.puts("\n✓ Skills orchestration demo passed semantic checks")
