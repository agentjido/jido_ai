defmodule Jido.AI.Actions.Skill.LoadSkillTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Actions.Skill.LoadSkill
  alias Jido.AI.Skill.{Registry, Spec}

  setup do
    start_supervised!(Registry)

    :ok =
      Registry.register(%Spec{
        name: "insights",
        description: "Analyze product signals.",
        body_ref: {:inline, "# Insights\n\nFollow the product analysis workflow."},
        allowed_tools: ["read_file", "search"],
        tags: ["product", "analyst"],
        metadata: %{owner: "research"},
        license: "MIT",
        compatibility: ">= 2.0.0",
        vsn: "1.2.3"
      })

    :ok
  end

  describe "schema" do
    test "has expected fields" do
      assert LoadSkill.schema().fields[:name].meta.required == true
      assert LoadSkill.schema().fields[:include_metadata].value == true
    end
  end

  describe "run/2" do
    test "loads full instructions for a registered skill" do
      assert {:ok, result} = LoadSkill.run(%{name: "insights"}, %{})

      assert result.name == "insights"
      assert result.description == "Analyze product signals."
      assert result.instructions == "# Insights\n\nFollow the product analysis workflow."
      assert result.allowed_tools == ["read_file", "search"]
      assert result.tags == ["product", "analyst"]
      assert result.metadata == %{owner: "research"}
      assert result.license == "MIT"
      assert result.compatibility == ">= 2.0.0"
      assert result.vsn == "1.2.3"
    end

    test "can omit metadata fields" do
      assert {:ok, result} = LoadSkill.run(%{name: "insights", include_metadata: false}, %{})

      assert result == %{
               name: "insights",
               description: "Analyze product signals.",
               instructions: "# Insights\n\nFollow the product analysis workflow."
             }
    end

    test "trims skill names before lookup" do
      assert {:ok, result} = LoadSkill.run(%{name: " insights "}, %{})
      assert result.name == "insights"
    end

    test "returns structured error with available skills when missing" do
      assert {:error, error} = LoadSkill.run(%{name: "missing"}, %{})

      assert error.type == :skill_not_found
      assert error.message == "Unknown skill 'missing'"
      assert error.available_skills == ["insights"]
    end

    test "rejects missing or blank skill names" do
      assert {:error, %{type: :invalid_skill_name}} = LoadSkill.run(%{}, %{})
      assert {:error, %{type: :invalid_skill_name}} = LoadSkill.run(%{name: "  "}, %{})
    end
  end
end
