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
      assert result.root_dir == nil
      assert result.resources == %{scripts: [], references: [], assets: []}
    end

    test "can omit metadata fields" do
      assert {:ok, result} = LoadSkill.run(%{name: "insights", include_metadata: false}, %{})

      assert result == %{
               name: "insights",
               description: "Analyze product signals.",
               instructions: "# Insights\n\nFollow the product analysis workflow.",
               root_dir: nil,
               resources: %{scripts: [], references: [], assets: []}
             }
    end

    test "trims skill names before lookup" do
      assert {:ok, result} = LoadSkill.run(%{name: " insights "}, %{})
      assert result.name == "insights"
    end

    test "accepts string-keyed tool parameters" do
      assert {:ok, result} = LoadSkill.run(%{"name" => "insights", "include_metadata" => false}, %{})

      assert result == %{
               name: "insights",
               description: "Analyze product signals.",
               instructions: "# Insights\n\nFollow the product analysis workflow.",
               root_dir: nil,
               resources: %{scripts: [], references: [], assets: []}
             }
    end

    test "returns structured error with available skills when missing" do
      assert {:error, error} = LoadSkill.run(%{name: "missing"}, %{})

      assert error.type == :skill_not_found
      assert error.message == "Unknown skill 'missing'"
      assert error.available_skills == ["insights"]
    end

    test "does not fall through a scoped catalog to the global registry" do
      context = %{LoadSkill.context_skills_key() => %{}, agent_id: "scoped-agent"}

      assert {:error, error} = LoadSkill.run(%{name: "insights"}, context)
      assert error.type == :skill_not_found
      assert error.available_skills == []
      refute Registry.activated?("insights", session_id: "scoped-agent")
    end

    test "returns structured error when a skill body file is unavailable" do
      missing_path = Path.join(System.tmp_dir!(), "missing-skill-#{System.unique_integer([:positive])}.md")

      :ok =
        Registry.register(%Spec{
          name: "file-backed",
          description: "Loads from disk.",
          body_ref: {:file, missing_path}
        })

      assert {:error, error} = LoadSkill.run(%{name: "file-backed"}, %{})

      assert error.type == :skill_body_unavailable
      assert error.message == "Could not load skill body for 'file-backed'"
      assert error.reason == :enoent
    end

    test "rejects missing, blank, or invalid skill names" do
      assert {:error, %{type: :invalid_skill_name}} = LoadSkill.run(%{}, %{})
      assert {:error, %{type: :invalid_skill_name}} = LoadSkill.run(%{name: "  "}, %{})

      assert {:error, %{type: :invalid_skill_name, reason: :invalid_format}} =
               LoadSkill.run(%{name: "Invalid_Name"}, %{})

      assert {:error, %{type: :invalid_skill_name, reason: :string_too_long}} =
               LoadSkill.run(%{name: String.duplicate("a", 65)}, %{})
    end

    test "rejects invalid include_metadata values" do
      assert {:error, error} = LoadSkill.run(%{name: "insights", include_metadata: "false"}, %{})

      assert error.type == :invalid_include_metadata
      assert error.message == "include_metadata must be a boolean"
    end

    test "rejects non-map parameters" do
      assert {:error, error} = LoadSkill.run([], %{})

      assert error.type == :invalid_params
      assert error.message == "Parameters must be a map"
    end

    test "activates and deduplicates within the runtime session only" do
      assert {:ok, _result} = LoadSkill.run(%{name: "insights"}, %{agent_id: "agent-a"})

      assert Registry.activated?("insights", session_id: "agent-a")
      refute Registry.durable?("insights", session_id: "agent-a")
      refute Registry.activated?("insights", session_id: "agent-b")

      assert {:ok, _result} = LoadSkill.run(%{name: "insights"}, %{agent_id: "agent-b"})
      assert Registry.activated?("insights", session_id: "agent-b")
    end
  end
end
