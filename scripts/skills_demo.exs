# Skills Demo - Module and File-based Skills
#
# Demonstrates Jido.AI.Skill with both:
# 1. Module-based skill (Calculator) - defined with `use Jido.AI.Skill`
# 2. File-based skill (Unit Converter) - loaded from YAML SKILL.md
#
# Run with: mix run scripts/skills_demo.exs
#
# Prerequisites:
# - ANTHROPIC_API_KEY environment variable set
# - priv/skills/unit-converter/SKILL.md exists

alias Jido.AI.Skill
alias Jido.AI.Skill.{Registry, Loader, Prompt}
alias Jido.AI.Examples.SkillsDemoAgent
alias Jido.AI.Examples.Skills.Calculator

IO.puts("\n" <> String.duplicate("=", 70))
IO.puts("Jido.AI Skills Demo - Module + File-based Skills")
IO.puts(String.duplicate("=", 70))

# -----------------------------------------------------------------------------
# Part 1: Skill Introspection (no LLM needed)
# -----------------------------------------------------------------------------

IO.puts("\n📦 PART 1: Skill Introspection\n")

# Module-based skill
IO.puts("── Module Skill: Calculator ──")
IO.puts("Name: #{Skill.manifest(Calculator).name}")
IO.puts("Description: #{Skill.manifest(Calculator).description}")
IO.puts("Allowed tools: #{inspect(Skill.allowed_tools(Calculator))}")
IO.puts("Actions: #{inspect(Skill.actions(Calculator))}")
IO.puts("")

# File-based skill - first load it
IO.puts("── File Skill: Unit Converter ──")
IO.puts("Loading from priv/skills/unit-converter/SKILL.md...")

case Loader.load("priv/skills/unit-converter/SKILL.md") do
  {:ok, spec} ->
    IO.puts("Name: #{spec.name}")
    IO.puts("Description: #{spec.description}")
    IO.puts("Allowed tools: #{inspect(spec.allowed_tools)}")
    IO.puts("Tags: #{inspect(spec.tags)}")
    IO.puts("License: #{spec.license}")

  {:error, reason} ->
    IO.puts("Failed to load: #{inspect(reason)}")
    System.halt(1)
end

# -----------------------------------------------------------------------------
# Part 2: Registry and Prompt Rendering
# -----------------------------------------------------------------------------

IO.puts("\n📝 PART 2: Registry & Prompt Rendering\n")

# Start the registry and load skills
{:ok, _} = Registry.start_link()
{:ok, count} = Registry.load_from_paths(["priv/skills"])
IO.puts("Loaded #{count} skill(s) from priv/skills/")
IO.puts("Registered skills: #{inspect(Registry.list())}")

# Render combined prompt
IO.puts("\n── Combined Skill Prompt ──")
skills = [Calculator, "unit-converter"]
prompt = Prompt.render(skills)
IO.puts(prompt)

# -----------------------------------------------------------------------------
# Part 3: Agent Interaction (requires API key)
# -----------------------------------------------------------------------------

IO.puts("\n" <> String.duplicate("=", 70))
IO.puts("🤖 PART 3: Agent Interaction")
IO.puts(String.duplicate("=", 70))

if System.get_env("ANTHROPIC_API_KEY") do
  # Start Jido and the agent
  {:ok, _jido} = Jido.start_link(name: SkillsDemo.Jido)
  {:ok, pid} = Jido.start_agent(SkillsDemo.Jido, SkillsDemoAgent)

  # Questions that exercise both skills
  questions = [
    # Calculator skill
    {"Calculator", "What is 42 * 17 + 100?"},
    # Unit converter skill
    {"Unit Converter", "Convert 98.6 degrees Fahrenheit to Celsius"},
    # Combined reasoning
    {"Combined", "If I run a 5K (5 kilometers), how many miles is that? And if I burn 100 calories per mile, how many total calories?"}
  ]

  for {skill_name, question} <- questions do
    IO.puts("\n[#{skill_name}] #{question}")
    IO.puts(String.duplicate("-", 60))

    case SkillsDemoAgent.ask_sync(pid, question, timeout: 60_000) do
      {:ok, reply} ->
        IO.puts(reply)

      {:error, reason} ->
        IO.puts("[ERROR] #{inspect(reason)}")
    end
  end

  GenServer.stop(pid)
else
  IO.puts("\n⚠️  ANTHROPIC_API_KEY not set - skipping agent interaction")
  IO.puts("   Set the environment variable to see the full demo:")
  IO.puts("   export ANTHROPIC_API_KEY=your-key-here")
end

IO.puts("\n" <> String.duplicate("=", 70))
IO.puts("Demo complete!")
IO.puts(String.duplicate("=", 70) <> "\n")
