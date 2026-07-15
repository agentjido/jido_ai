defmodule Jido.AI.Skill.AgentIntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.Skill.LoadSkill
  alias Jido.AI.Skill.AgentIntegration

  @moduletag :tmp_dir

  test "disabled integration is empty" do
    assert {:ok, %{specs: [], index: "", tools: [], tool_context: %{}}} =
             AgentIntegration.prepare(false)

    assert {:ok, %{specs: [], index: "", tools: [], tool_context: %{}}} =
             AgentIntegration.prepare([])
  end

  test "prepares progressive disclosure from explicitly trusted roots", %{tmp_dir: tmp_dir} do
    skill_dir = Path.join(tmp_dir, "review")
    File.mkdir_p!(Path.join(skill_dir, "references"))

    File.write!(Path.join(skill_dir, "SKILL.md"), """
    ---
    name: review
    description: Review code when asked for feedback.
    ---

    # Review instructions
    """)

    File.write!(Path.join([skill_dir, "references", "checks.md"]), "Checks")

    assert {:ok, integration} = AgentIntegration.prepare([tmp_dir])
    assert [LoadSkill] == integration.tools
    assert integration.index =~ "**review**"
    refute integration.index =~ "# Review instructions"

    specs = integration.tool_context[LoadSkill.context_skills_key()]
    assert specs["review"].body_ref == {:inline, "# Review instructions"}
  end

  test "supports an explicit trust gate", %{tmp_dir: tmp_dir} do
    assert {:error, {:untrusted_skill_path, path}} =
             AgentIntegration.prepare(paths: [tmp_dir])

    assert path == Path.expand(tmp_dir)
  end

  test "rejects invalid path entries" do
    assert {:error, {:invalid_agent_skills_option, :paths}} =
             AgentIntegration.prepare([:not_a_path])
  end
end
