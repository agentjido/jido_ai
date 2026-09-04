defmodule Jido.AI.Skill.AgentIntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.Skill.{LoadResource, LoadSkill}
  alias Jido.AI.Skill.{AgentIntegration, ResourceProvider, Resources, Spec}

  @moduletag :tmp_dir

  test "disabled integration is empty" do
    assert {:ok, %{specs: [], index: "", tools: [], tool_context: %{}, diagnostics: diagnostics}} =
             AgentIntegration.prepare(false)

    assert diagnostics.warnings == []

    assert {:ok, %{specs: [], index: "", tools: [], tool_context: %{}, diagnostics: diagnostics}} =
             AgentIntegration.prepare([])

    assert diagnostics.warnings == []
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
    assert [LoadSkill, LoadResource] == integration.tools
    assert integration.index =~ "**review**"
    refute integration.index =~ "# Review instructions"

    specs = integration.tool_context[LoadSkill.context_skills_key()]
    assert specs["review"].body_ref == {:file, Path.join(skill_dir, "SKILL.md")}
    refute inspect(specs["review"]) =~ "# Review instructions"
  end

  test "validates and provides a custom resource policy", %{tmp_dir: tmp_dir} do
    skill_dir = Path.join(tmp_dir, "bounded")
    File.mkdir_p!(skill_dir)
    File.write!(Path.join(skill_dir, "SKILL.md"), "---\nname: bounded\ndescription: Bounded.\n---\n")

    assert {:ok, integration} =
             AgentIntegration.prepare(
               paths: [tmp_dir],
               trust: true,
               resource_policy: [max_text_bytes: 128]
             )

    policy = integration.tool_context[Resources.context_policy_key()]
    assert policy.max_text_bytes == 128

    assert {:error, {:invalid_resource_policy, :max_file_bytes}} =
             AgentIntegration.prepare(
               paths: [tmp_dir],
               trust: true,
               resource_policy: [max_file_bytes: 0]
             )
  end

  test "prepares runtime-only specs without filesystem discovery" do
    provider = fn _request, _context -> {:ok, %{resources: [], complete: true}} end

    spec = %Spec{
      name: "runtime-only",
      description: "Runtime supplied skill.",
      body_ref: {:inline, "Runtime body."},
      metadata: %{"source" => "host"},
      tags: ["runtime"]
    }

    assert {:ok, integration} = AgentIntegration.prepare(specs: [spec], resource_provider: provider)
    assert integration.specs == [spec]
    assert integration.index =~ "**runtime-only**"
    assert integration.tools == [LoadSkill, LoadResource]

    catalog = integration.tool_context[LoadSkill.context_skills_key()]
    assert catalog["runtime-only"] == spec
    assert integration.tool_context[ResourceProvider.context_provider_key()] == provider
  end

  test "runtime specs take precedence over discovered paths and report shadowed duplicates", %{tmp_dir: tmp_dir} do
    discovered_path = write_skill(tmp_dir, "shared", "Discovered skill.")

    runtime_spec = %Spec{
      name: "shared",
      description: "Runtime skill.",
      body_ref: {:inline, "Runtime body."}
    }

    assert {:ok, integration} = AgentIntegration.prepare(specs: [runtime_spec], paths: [tmp_dir], trust: true)
    assert integration.specs == [runtime_spec]
    assert integration.index =~ "Runtime skill."
    refute integration.index =~ "Discovered skill."

    assert [warning] = Enum.filter(integration.diagnostics.warnings, &(&1.type == :shadowed_skill))
    assert warning.message =~ discovered_path
    assert warning.message =~ "runtime spec"
  end

  test "rejects duplicate and invalid runtime specs" do
    first = %Spec{name: "dup", description: "First.", body_ref: {:inline, "Body."}}
    second = %Spec{name: "dup", description: "Second.", body_ref: {:inline, "Body."}}

    assert {:error, {:duplicate_runtime_skill, "dup", 0, 1}} =
             AgentIntegration.prepare(specs: [first, second])

    invalid = %Spec{name: "bad", description: "Bad.", body_ref: nil}

    assert {:error,
            {:invalid_runtime_skill_spec, 0,
             %Jido.AI.Skill.Error.Validation.InvalidField{field: :body_ref, reason: :inline_body_required}}} =
             AgentIntegration.prepare(specs: [invalid])
  end

  test "rejects runtime specs with filesystem sources" do
    spec = %Spec{
      name: "runtime-source",
      description: "Runtime source.",
      source: {:file, "/tmp/runtime-source/SKILL.md"},
      body_ref: {:inline, "Body."}
    }

    assert {:error,
            {:invalid_runtime_skill_spec, 0,
             %Jido.AI.Skill.Error.Validation.InvalidField{field: :source, reason: :must_be_nil}}} =
             AgentIntegration.prepare(specs: [spec])
  end

  test "rejects invalid resource providers" do
    spec = %Spec{name: "runtime-provider", description: "Runtime provider.", body_ref: {:inline, "Body."}}

    assert {:error, {:invalid_resource_provider, :invalid_form}} =
             AgentIntegration.prepare(specs: [spec], resource_provider: :bad_provider)
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

  test "reports duplicate names and catalogs only the first trusted root", %{tmp_dir: tmp_dir} do
    first_root = Path.join(tmp_dir, "z-first")
    second_root = Path.join(tmp_dir, "a-second")
    first_path = write_skill(first_root, "shared", "First root wins.")
    second_path = write_skill(second_root, "shared", "Second root is shadowed.")

    assert {:ok, integration} = AgentIntegration.prepare([first_root, second_root])
    assert [%{name: "shared", description: "First root wins."}] = integration.specs
    assert integration.index =~ "First root wins."
    refute integration.index =~ "Second root is shadowed."

    assert [warning] = Enum.filter(integration.diagnostics.warnings, &(&1.type == :shadowed_skill))
    assert warning.message =~ first_path
    assert warning.message =~ second_path
  end

  test "rejects specification-invalid skills instead of silently normalizing them", %{tmp_dir: tmp_dir} do
    skill_dir = Path.join(tmp_dir, "actual-name")
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      "---\nname: different-name\ndescription: Invalid directory match\n---\n"
    )

    assert {:error,
            {:skill_load_failed, _path,
             %Jido.AI.Skill.Error.Validation.InvalidField{
               field: :name,
               reason: :directory_name_mismatch
             }}} = AgentIntegration.prepare([tmp_dir])
  end

  defp write_skill(root, name, description) do
    skill_dir = Path.join(root, name)
    File.mkdir_p!(skill_dir)
    path = Path.join(skill_dir, "SKILL.md")
    File.write!(path, "---\nname: #{name}\ndescription: #{description}\n---\nBody.\n")
    path
  end
end
