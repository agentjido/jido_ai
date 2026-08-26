defmodule Jido.AI.Actions.Skill.LoadSkillTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Actions.Skill.LoadSkill
  alias Jido.AI.Skill.{Discovery, Registry, Resources, Spec}

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
      assert result.resources.resources == []
      assert result.resources.complete
    end

    test "can omit metadata fields" do
      assert {:ok, result} = LoadSkill.run(%{name: "insights", include_metadata: false}, %{})

      assert %{
               name: "insights",
               description: "Analyze product signals.",
               instructions: "# Insights\n\nFollow the product analysis workflow.",
               root_dir: nil,
               resources: %{resources: [], scripts: [], references: [], assets: [], complete: true}
             } = result
    end

    test "trims skill names before lookup" do
      assert {:ok, result} = LoadSkill.run(%{name: " insights "}, %{})
      assert result.name == "insights"
    end

    test "accepts string-keyed tool parameters" do
      assert {:ok, result} = LoadSkill.run(%{"name" => "insights", "include_metadata" => false}, %{})

      assert %{
               name: "insights",
               description: "Analyze product signals.",
               instructions: "# Insights\n\nFollow the product analysis workflow.",
               root_dir: nil,
               resources: %{resources: [], scripts: [], references: [], assets: [], complete: true}
             } = result
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

    @tag :tmp_dir
    test "strictly loads the current file from a scoped lazy catalog", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "lazy-action")
      skill_path = Path.join(skill_dir, "SKILL.md")
      File.mkdir_p!(skill_dir)

      File.write!(
        skill_path,
        "---\nname: lazy-action\ndescription: Lazy action.\n---\nInitial body.\n"
      )

      assert {:ok, [metadata]} = Discovery.discover_from([tmp_dir])
      assert {:ok, catalog_spec} = Discovery.to_catalog_spec(metadata)

      File.write!(
        skill_path,
        "---\nname: lazy-action\ndescription: Updated action.\n---\nUpdated body.\n"
      )

      context = %{
        LoadSkill.context_skills_key() => %{"lazy-action" => catalog_spec},
        agent_id: "lazy-agent"
      }

      assert {:ok, result} = LoadSkill.run(%{name: "lazy-action"}, context)
      assert result.description == "Updated action."
      assert result.instructions == "Updated body."
      assert result.metadata["jido_ai.discovery_scope"] == "custom"
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

    test "returns a structured error for an invalid context resource policy" do
      context = %{Resources.context_policy_key() => [max_text_bytes: 0]}

      assert {:error, error} = LoadSkill.run(%{name: "insights"}, context)
      assert error.type == :invalid_resource_policy
      assert error.reason == {:invalid_resource_policy, :max_text_bytes}
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
