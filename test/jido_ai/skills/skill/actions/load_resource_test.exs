defmodule Jido.AI.Actions.Skill.LoadResourceTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Actions.Skill.{LoadResource, LoadSkill}
  alias Jido.AI.Skill.{Activation, AgentIntegration, Registry, Spec}

  @moduletag :tmp_dir

  setup do
    start_supervised!(Registry)
    :ok
  end

  describe "schema" do
    test "requires a skill name and resource path" do
      assert LoadResource.schema().fields[:name].meta.required == true
      assert LoadResource.schema().fields[:path].meta.required == true
    end
  end

  describe "run/2" do
    test "loads text only from an activated skill in the same session", %{tmp_dir: tmp_dir} do
      activate_skill(tmp_dir, "resource-skill", "agent-a")
      File.mkdir_p!(Path.join(tmp_dir, "references"))
      File.write!(Path.join(tmp_dir, "references/guide.md"), "Guide text")

      assert {:ok, result} =
               LoadResource.run(
                 %{name: "resource-skill", path: "references/guide.md"},
                 %{agent_id: "agent-a"}
               )

      assert result == %{
               skill: "resource-skill",
               path: "references/guide.md",
               content: "Guide text",
               size: 10
             }

      assert {:error, %{type: :skill_not_activated}} =
               LoadResource.run(
                 %{name: "resource-skill", path: "references/guide.md"},
                 %{agent_id: "agent-b"}
               )
    end

    test "requires prior skill activation", %{tmp_dir: _tmp_dir} do
      assert {:error, error} =
               LoadResource.run(%{name: "inactive", path: "guide.md"}, %{agent_id: "agent-a"})

      assert error.type == :skill_not_activated
      assert error.skill == "inactive"
    end

    test "returns structured invalid and missing path errors", %{tmp_dir: tmp_dir} do
      activate_skill(tmp_dir, "safe-skill", "safe-agent")
      context = %{agent_id: "safe-agent"}

      assert {:error, %{type: :invalid_resource_path}} =
               LoadResource.run(%{name: "safe-skill", path: "../outside.txt"}, context)

      assert {:error, %{type: :invalid_resource_path}} =
               LoadResource.run(%{name: "safe-skill", path: "SKILL.md"}, context)

      assert {:error, %{type: :invalid_resource_path}} =
               LoadResource.run(%{name: "safe-skill", path: "./SKILL.md"}, context)

      assert {:error, %{type: :resource_not_found}} =
               LoadResource.run(%{name: "safe-skill", path: "missing.txt"}, context)
    end

    test "returns structured oversized and binary errors", %{tmp_dir: tmp_dir} do
      activate_skill(tmp_dir, "bounded-skill", "bounded-agent", max_text_bytes: 4)
      File.write!(Path.join(tmp_dir, "large.txt"), "12345")
      File.write!(Path.join(tmp_dir, "binary.bin"), <<0xFF, 0xFE>>)
      File.write!(Path.join(tmp_dir, "nul.bin"), <<0, 0, 0>>)
      context = %{agent_id: "bounded-agent"}

      assert {:error, oversized} =
               LoadResource.run(%{name: "bounded-skill", path: "large.txt"}, context)

      assert oversized.type == :resource_too_large
      assert oversized.limit_kind == :text
      assert oversized.size == 5
      assert oversized.limit == 4

      assert {:error, %{type: :binary_resource}} =
               LoadResource.run(%{name: "bounded-skill", path: "binary.bin"}, context)

      assert {:error, %{type: :binary_resource}} =
               LoadResource.run(%{name: "bounded-skill", path: "nul.bin"}, context)
    end

    test "uses the agent integration policy after load_skill activation", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "integrated-skill")
      File.mkdir_p!(Path.join(skill_dir, "custom"))

      File.write!(
        Path.join(skill_dir, "SKILL.md"),
        "---\nname: integrated-skill\ndescription: Integrated skill.\n---\nInstructions.\n"
      )

      File.write!(Path.join(skill_dir, "custom/data.txt"), "12345")

      assert {:ok, integration} =
               AgentIntegration.prepare(
                 paths: [tmp_dir],
                 trust: true,
                 resource_policy: [max_text_bytes: 4]
               )

      context = Map.put(integration.tool_context, :agent_id, "integrated-agent")
      assert {:ok, loaded} = LoadSkill.run(%{name: "integrated-skill"}, context)
      assert Enum.map(loaded.resources.resources, & &1.relative_path) == ["custom/data.txt"]

      assert {:error, %{type: :resource_too_large, limit: 4}} =
               LoadResource.run(%{name: "integrated-skill", path: "custom/data.txt"}, context)
    end

    test "rejects invalid parameters" do
      assert {:error, %{type: :invalid_params}} = LoadResource.run([], %{})
      assert {:error, %{type: :invalid_skill_name}} = LoadResource.run(%{path: "file.txt"}, %{})

      assert {:error, %{type: :invalid_resource_path}} =
               LoadResource.run(%{name: "valid-name", path: ""}, %{})
    end
  end

  defp activate_skill(root, name, session_id, policy_opts \\ []) do
    skill_path = Path.join(root, "SKILL.md")
    File.write!(skill_path, "instructions")

    spec = %Spec{
      name: name,
      description: "Resource test skill.",
      body_ref: {:inline, "instructions"},
      source: {:file, skill_path}
    }

    assert {:ok, _activation} =
             Activation.activate(spec, session_id: session_id, resource_policy: policy_opts)
  end
end
