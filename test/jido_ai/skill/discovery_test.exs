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
      skill_dir = Path.join(tmp_dir, "to-spec")
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
      assert spec.metadata[:discovery_scope] == :project
    end
  end
end
