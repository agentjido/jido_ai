defmodule Jido.AI.Skill.PromptTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Skill.{Prompt, Spec, Registry}

  # Test module skill
  defmodule TestSkill do
    use Jido.AI.Skill,
      name: "test-skill",
      description: "A test skill.",
      allowed_tools: ~w(tool_a tool_b),
      body: """
      # Test Skill Body

      Use this for testing.
      """
  end

  defmodule MinimalSkill do
    use Jido.AI.Skill,
      name: "minimal",
      description: "Minimal skill with no tools."
  end

  defmodule TaggedSkill do
    use Jido.AI.Skill,
      name: "tagged-skill",
      description: """
      Helps tagged agents.
      Use when the agent needs scoped instructions.
      """,
      allowed_tools: ~w(load_skill),
      tags: ["support", "agent-a"],
      body: """
      # Tagged Skill Body
      """
  end

  # Mock tool modules
  defmodule MockToolA do
    def name, do: "tool_a"
  end

  defmodule MockToolB do
    def name, do: "tool_b"
  end

  defmodule MockToolC do
    def name, do: "tool_c"
  end

  setup do
    start_supervised!(Registry)
    :ok
  end

  describe "render/2" do
    test "omits skill bodies by default" do
      result = Prompt.render([TestSkill])

      assert result =~ "You have access to the following skills:"
      assert result =~ "## test-skill"
      assert result =~ "A test skill."
      assert result =~ "Allowed tools: tool_a, tool_b"
      refute result =~ "# Test Skill Body"
    end

    test "renders multiple skills" do
      result = Prompt.render([TestSkill, MinimalSkill])

      assert result =~ "## test-skill"
      assert result =~ "## minimal"
    end

    test "includes bodies only when explicitly requested" do
      result = Prompt.render([TestSkill], include_body: true)

      assert result =~ "## test-skill"
      assert result =~ "# Test Skill Body"
    end

    test "uses custom header" do
      result = Prompt.render([TestSkill], header: "Active skills:")

      assert result =~ "Active skills:"
      refute result =~ "You have access"
    end

    test "returns empty string for empty list" do
      result = Prompt.render([])
      assert result == ""
    end

    test "handles unknown skills gracefully" do
      result = Prompt.render([TestSkill, "nonexistent-skill"])

      assert result =~ "## test-skill"
      refute result =~ "nonexistent"
    end
  end

  describe "render_one/2" do
    test "renders single skill" do
      result = Prompt.render_one(TestSkill)

      assert result =~ "## test-skill"
      assert result =~ "# Test Skill Body"
    end

    test "renders skill without body" do
      result = Prompt.render_one(TestSkill, include_body: false)

      assert result =~ "## test-skill"
      refute result =~ "# Test Skill Body"
    end

    test "returns empty string for unknown skill" do
      result = Prompt.render_one("unknown")
      assert result == ""
    end
  end

  describe "render_index/2" do
    test "renders compact entries without skill bodies" do
      result = Prompt.render_index([TestSkill, TaggedSkill], include_allowed_tools: true)

      assert result =~ "## Skills"
      assert result =~ "* **test-skill**: A test skill. (tools: tool_a, tool_b)"
      assert result =~ "* **tagged-skill**: Helps tagged agents.\n  Use when the agent needs scoped instructions."
      assert result =~ "call `load_skill`"
      refute result =~ "# Test Skill Body"
      refute result =~ "# Tagged Skill Body"
    end

    test "filters compact entries by any tag" do
      result = Prompt.render_index([TestSkill, TaggedSkill], tags: ["agent-a"])

      assert result =~ "tagged-skill"
      refute result =~ "test-skill"
    end

    test "filters compact entries by all tags" do
      result = Prompt.render_index([TaggedSkill], tags: ["support", "agent-a"], tag_match: :all)
      assert result =~ "tagged-skill"

      result = Prompt.render_index([TaggedSkill], tags: ["support", "agent-b"], tag_match: :all)
      assert result == ""
    end

    test "can omit header and load instruction" do
      result = Prompt.render_index([TestSkill], header: false, load_instruction: false)

      assert result == "* **test-skill**: A test skill."
    end
  end

  describe "render_registry_index/1" do
    test "renders registered skills filtered by tag" do
      Registry.register(%{
        TaggedSkill.manifest()
        | name: "runtime-agent-skill",
          tags: ["agent-b"]
      })

      Registry.register(%{
        TestSkill.manifest()
        | name: "runtime-other-skill",
          tags: ["other"]
      })

      result = Prompt.render_registry_index(tags: "agent-b")

      assert result =~ "runtime-agent-skill"
      refute result =~ "runtime-other-skill"
    end
  end

  describe "collect_allowed_tools/1" do
    test "collects tools from single skill" do
      tools = Prompt.collect_allowed_tools([TestSkill])
      assert tools == ["tool_a", "tool_b"]
    end

    test "collects union of tools from multiple skills" do
      # Register a runtime skill with different tools
      spec = %Spec{
        name: "other-skill",
        description: "Other",
        allowed_tools: ["tool_b", "tool_c"]
      }

      Registry.register(spec)

      tools = Prompt.collect_allowed_tools([TestSkill, "other-skill"])

      assert "tool_a" in tools
      assert "tool_b" in tools
      assert "tool_c" in tools
      assert length(tools) == 3
    end

    test "returns empty list for skills with no allowed tools" do
      tools = Prompt.collect_allowed_tools([MinimalSkill])
      assert tools == []
    end

    test "handles unknown skills" do
      tools = Prompt.collect_allowed_tools([TestSkill, "unknown"])
      assert tools == ["tool_a", "tool_b"]
    end
  end

  describe "filter_tools/2" do
    test "filters tools by allowed tools" do
      all_tools = [MockToolA, MockToolB, MockToolC]
      filtered = Prompt.filter_tools(all_tools, [TestSkill])

      assert MockToolA in filtered
      assert MockToolB in filtered
      refute MockToolC in filtered
    end

    test "returns all tools if no skills specify allowed_tools" do
      all_tools = [MockToolA, MockToolB, MockToolC]
      filtered = Prompt.filter_tools(all_tools, [MinimalSkill])

      assert filtered == all_tools
    end

    test "returns all tools if skill list is empty" do
      all_tools = [MockToolA, MockToolB, MockToolC]
      filtered = Prompt.filter_tools(all_tools, [])

      assert filtered == all_tools
    end

    test "handles mixed skills with and without allowed_tools" do
      all_tools = [MockToolA, MockToolB, MockToolC]

      # MinimalSkill has no allowed_tools, TestSkill has tool_a and tool_b
      # Union should be tool_a, tool_b (from TestSkill)
      filtered = Prompt.filter_tools(all_tools, [TestSkill, MinimalSkill])

      assert MockToolA in filtered
      assert MockToolB in filtered
      refute MockToolC in filtered
    end
  end
end
