defmodule Jido.AI.Examples.SkillsDemoAgent do
  @moduledoc """
  Demonstration agent using both module-based and file-based skills.

  This agent combines:
  - **Calculator skill** (module-based) - `Jido.AI.Examples.Skills.Calculator`
  - **Unit Converter skill** (YAML file) - loaded from `priv/skills/unit-converter/SKILL.md`

  ## Usage

      # Ensure the registry is started and skill is loaded
      Jido.AI.Skill.Registry.start_link()
      Jido.AI.Skill.Registry.load_from_paths(["priv/skills"])

      # Start the agent
      {:ok, pid} = Jido.start_agent(MyJido, Jido.AI.Examples.SkillsDemoAgent)

      # Ask questions that use both skills
      Jido.AI.Examples.SkillsDemoAgent.ask_sync(pid, "What is 25 * 4?")
      Jido.AI.Examples.SkillsDemoAgent.ask_sync(pid, "Convert 100°F to Celsius")
  """

  alias Jido.AI.Skill.Prompt

  @calculator_skill Jido.AI.Examples.Skills.Calculator
  @unit_converter_skill "unit-converter"

  use Jido.AI.Agent,
    name: "skills_demo_agent",
    description: "Demo agent showcasing module and file-based skills",
    tools: [
      Jido.Tools.Arithmetic.Add,
      Jido.Tools.Arithmetic.Subtract,
      Jido.Tools.Arithmetic.Multiply,
      Jido.Tools.Arithmetic.Divide,
      Jido.AI.Examples.Tools.ConvertTemperature,
      Jido.AI.Examples.Tools.ConvertDistance,
      Jido.AI.Examples.Tools.ConvertWeight
    ],
    system_prompt: """
    You are a helpful assistant with specialized skills for calculations and unit conversions.
    Always use the appropriate tools for arithmetic and conversions - never guess or do mental math.
    Show your work clearly and provide helpful explanations.
    """,
    max_iterations: 10

  @doc """
  Returns the list of skills used by this agent.
  """
  def skills do
    [@calculator_skill, @unit_converter_skill]
  end

  @doc """
  Builds the full system prompt including skill instructions.

  Call this after the skill registry is loaded to include file-based skills.
  """
  def build_system_prompt do
    base = """
    You are a helpful assistant with specialized skills for calculations and unit conversions.
    Always use the appropriate tools for arithmetic and conversions - never guess or do mental math.
    Show your work clearly and provide helpful explanations.
    """

    skill_prompt = Prompt.render(skills())
    base <> "\n\n" <> skill_prompt
  end

  @doc """
  Renders just the skill sections (for inspection/debugging).
  """
  def render_skills do
    Prompt.render(skills())
  end
end
