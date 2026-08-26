defmodule Jido.AI.Skill.DiscoveryTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skill.Discovery

  @moduletag :tmp_dir

  describe "discover_from/2" do
    test "returns empty list for empty directory", %{tmp_dir: tmp_dir} do
      assert {:ok, []} = Discovery.discover_from([tmp_dir])
    end

    test "discovers skills with valid frontmatter", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "review")
      File.mkdir_p!(skill_dir)

      File.write!(Path.join(skill_dir, "SKILL.md"), """
      ---
      name: code-review
      description: Review code for issues
      ---

      Body here.
      """)

      assert {:ok, [skill]} = Discovery.discover_from([tmp_dir])
      assert skill.name == "code-review"
      assert skill.description == "Review code for issues"
      assert skill.scope == :custom
      assert skill.skill_md_path == Path.join(skill_dir, "SKILL.md")
      assert skill.root_dir == skill_dir
    end

    test "ignores skills without frontmatter", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "bad")
      File.mkdir_p!(skill_dir)
      File.write!(Path.join(skill_dir, "SKILL.md"), "No frontmatter here.")

      assert {:ok, []} = Discovery.discover_from([tmp_dir])
    end

    test "ignores skills without name in frontmatter", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "bad")
      File.mkdir_p!(skill_dir)

      File.write!(Path.join(skill_dir, "SKILL.md"), """
      ---
      description: Missing name
      ---

      Body.
      """)

      assert {:ok, []} = Discovery.discover_from([tmp_dir])
    end

    test "ignores skills with non-string names in frontmatter", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "bad-name-type")
      File.mkdir_p!(skill_dir)

      File.write!(Path.join(skill_dir, "SKILL.md"), """
      ---
      name: 123
      description: Invalid name type
      ---

      Body.
      """)

      assert {:ok, []} = Discovery.discover_from([tmp_dir])
    end

    test "discovers nested skills", %{tmp_dir: tmp_dir} do
      nested = Path.join([tmp_dir, "nested", "deep-skill"])
      File.mkdir_p!(nested)

      File.write!(Path.join(nested, "SKILL.md"), """
      ---
      name: deep-skill
      ---

      Deep body.
      """)

      assert {:ok, [skill]} = Discovery.discover_from([tmp_dir])
      assert skill.name == "deep-skill"
    end

    test "assigns scope from opts", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "scoped")
      File.mkdir_p!(skill_dir)

      File.write!(Path.join(skill_dir, "SKILL.md"), """
      ---
      name: scoped-skill
      ---

      Body.
      """)

      assert {:ok, [skill]} = Discovery.discover_from([tmp_dir], scope: :project)
      assert skill.scope == :project
    end

    test "discovers multiple skills from multiple paths", %{tmp_dir: tmp_dir} do
      dir1 = Path.join(tmp_dir, "a")
      dir2 = Path.join(tmp_dir, "b")
      File.mkdir_p!(dir1)
      File.mkdir_p!(dir2)

      File.write!(Path.join(dir1, "SKILL.md"), "---\nname: skill-a\n---\n")
      File.write!(Path.join(dir2, "SKILL.md"), "---\nname: skill-b\n---\n")

      assert {:ok, skills} = Discovery.discover_from([dir1, dir2])
      names = Enum.map(skills, & &1.name) |> Enum.sort()
      assert names == ["skill-a", "skill-b"]
    end

    test "rejects roots that are not trusted", %{tmp_dir: tmp_dir} do
      assert {:error, {:untrusted_skill_path, path}} =
               Discovery.discover_from([tmp_dir], trust: false)

      assert path == Path.expand(tmp_dir)
    end

    test "rejects malformed paths and trust policies" do
      assert {:error, {:invalid_discovery_option, :paths}} =
               Discovery.discover_from([:not_a_path])

      assert {:error, {:invalid_discovery_option, :trust}} =
               Discovery.discover_from([], trust: :implicit)

      assert {:error, {:invalid_discovery_option, :scope}} =
               Discovery.discover_from([], scope: :unknown)
    end

    test "honors depth bounds and excluded directories", %{tmp_dir: tmp_dir} do
      visible = Path.join(tmp_dir, "visible")
      too_deep = Path.join([tmp_dir, "one", "two"])
      excluded = Path.join([tmp_dir, "node_modules", "hidden"])

      for {directory, name} <- [{visible, "visible"}, {too_deep, "too-deep"}, {excluded, "hidden"}] do
        File.mkdir_p!(directory)
        File.write!(Path.join(directory, "SKILL.md"), "---\nname: #{name}\ndescription: test\n---\n")
      end

      assert {:ok, skills} = Discovery.discover_from([tmp_dir], max_depth: 1)
      assert Enum.map(skills, & &1.name) == ["visible"]
    end

    test "fails safely when the directory bound is exceeded", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "child"))

      assert {:error, {:discovery_limit_exceeded, :max_directories, 1}} =
               Discovery.discover_from([tmp_dir], max_directories: 1)
    end

    test "does not follow symlinked SKILL.md files", %{tmp_dir: tmp_dir} do
      trusted_root = Path.join(tmp_dir, "trusted")
      skill_dir = Path.join(trusted_root, "escaped")
      outside_dir = Path.join(tmp_dir, "outside")
      File.mkdir_p!(skill_dir)
      File.mkdir_p!(outside_dir)

      outside_skill = Path.join(outside_dir, "SKILL.md")
      File.write!(outside_skill, "---\nname: escaped\ndescription: Outside\n---\n")
      File.ln_s!(outside_skill, Path.join(skill_dir, "SKILL.md"))

      assert {:ok, []} = Discovery.discover_from([trusted_root])
    end

    test "uses earlier configured roots and reports shadowed skills", %{tmp_dir: tmp_dir} do
      first_root = Path.join(tmp_dir, "z-first")
      second_root = Path.join(tmp_dir, "a-second")
      first_skill = write_skill(first_root, "shared", "First root wins.")
      second_skill = write_skill(second_root, "shared", "Second root is shadowed.")

      assert {:ok, [selected], diagnostics} =
               Discovery.discover_from_with_diagnostics([first_root, second_root])

      assert selected.description == "First root wins."
      assert selected.skill_md_path == first_skill
      assert selected.source_metadata.shadowed_locations == [second_skill]

      assert [warning] = Enum.filter(diagnostics.warnings, &(&1.type == :shadowed_skill))
      assert warning.message =~ first_skill
      assert warning.message =~ second_skill
    end

    test "reads only frontmatter during discovery", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "binary-body")
      File.mkdir_p!(skill_dir)

      File.write!(
        Path.join(skill_dir, "SKILL.md"),
        "---\nname: binary-body\ndescription: Discovery stops before the body.\n---\n" <> <<0xFF, 0xFE>>
      )

      assert {:ok, [%{name: "binary-body"} = metadata]} = Discovery.discover_from([tmp_dir])
      refute Map.has_key?(metadata, :body)
    end

    test "ignores malformed YAML without raising", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "malformed")
      File.mkdir_p!(skill_dir)
      File.write!(Path.join(skill_dir, "SKILL.md"), "---\nname: [\n---\nBody.\n")

      assert {:ok, []} = Discovery.discover_from([tmp_dir])
    end
  end

  describe "discover_from_project/1" do
    test "returns empty list when project path does not exist", %{tmp_dir: tmp_dir} do
      missing = Path.join(tmp_dir, "no-such-skills-dir")
      assert {:ok, []} = Discovery.discover_from_project(missing)
    end
  end

  describe "discover_from_user/1" do
    test "returns empty list when user path does not exist", %{tmp_dir: tmp_dir} do
      missing = Path.join(tmp_dir, "no-such-skills-dir")
      assert {:ok, []} = Discovery.discover_from_user(missing)
    end
  end

  describe "find/1" do
    test "returns error when no skills exist" do
      assert {:error, :not_found} = Discovery.find("anything")
    end

    test "finds skill by name", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "found")
      File.mkdir_p!(skill_dir)

      File.write!(Path.join(skill_dir, "SKILL.md"), """
      ---
      name: find-me
      description: Found it
      ---

      Body.
      """)

      assert {:ok, skill} = Discovery.find("find-me", [tmp_dir])
      assert skill.name == "find-me"
      assert skill.description == "Found it"
    end
  end

  describe "to_spec/1" do
    test "returns error for invalid metadata" do
      assert {:error, _} = Discovery.to_spec(%{skill_md_path: "/nonexistent"})
    end

    test "converts metadata to spec with source", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "to-spec-skill")
      File.mkdir_p!(skill_dir)
      skill_md = Path.join(skill_dir, "SKILL.md")

      File.write!(skill_md, """
      ---
      name: to-spec-skill
      description: For spec conversion
      license: MIT
      ---

      Spec body.
      """)

      metadata = %{
        name: "to-spec-skill",
        description: "For spec conversion",
        skill_md_path: skill_md,
        root_dir: skill_dir,
        scope: :project,
        source_metadata: %{}
      }

      assert {:ok, spec} = Discovery.to_spec(metadata)
      assert spec.name == "to-spec-skill"
      assert spec.description == "For spec conversion"
      assert spec.license == "MIT"
      assert spec.source == {:file, skill_md}
      assert spec.metadata["jido_ai.discovery_scope"] == "project"
      assert Enum.all?(spec.metadata, fn {key, value} -> is_binary(key) and is_binary(value) end)
    end

    test "uses strict loading by default and keeps lenient loading explicit", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "strict-runtime")
      File.mkdir_p!(skill_dir)
      skill_md = Path.join(skill_dir, "SKILL.md")

      File.write!(
        skill_md,
        "---\nname: strict-runtime\ndescription: Runtime loading is strict.\ntags: [legacy]\n---\n"
      )

      metadata = %{
        name: "strict-runtime",
        description: "Runtime loading is strict.",
        skill_md_path: skill_md,
        root_dir: skill_dir,
        scope: :custom,
        source_metadata: %{}
      }

      assert {:error,
              %Jido.AI.Skill.Error.Validation.InvalidField{
                reason: :unsupported_top_level_fields
              }} = Discovery.to_spec(metadata)

      assert {:ok, %Jido.AI.Skill.Spec{}} = Discovery.to_spec(metadata, lenient: true)
    end

    test "creates a metadata-only catalog spec", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "catalog-only")
      skill_md = Path.join(skill_dir, "SKILL.md")

      metadata = %{
        name: "catalog-only",
        description: "Catalog metadata only.",
        skill_md_path: skill_md,
        root_dir: skill_dir,
        scope: :custom,
        source_metadata: %{}
      }

      assert {:ok, %Jido.AI.Skill.Spec{} = spec} = Discovery.to_catalog_spec(metadata)
      assert spec.body_ref == {:file, skill_md}
      assert spec.metadata == %{"jido_ai.discovery_scope" => "custom"}
    end
  end

  defp write_skill(root, name, description) do
    skill_dir = Path.join(root, name)
    File.mkdir_p!(skill_dir)
    path = Path.join(skill_dir, "SKILL.md")
    File.write!(path, "---\nname: #{name}\ndescription: #{description}\n---\nBody.\n")
    path
  end
end
