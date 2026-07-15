defmodule Jido.AI.Skill.LoaderTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skill.{Loader, Spec, Error}

  @fixtures_path Path.join([__DIR__, "..", "..", "fixtures", "skills"])

  setup do
    # Create fixtures directory and test files
    File.mkdir_p!(@fixtures_path)

    valid_skill = """
    ---
    name: test-skill
    description: A test skill for unit testing.
    license: MIT
    allowed-tools: tool_one tool_two
    metadata:
      author: test-author
      version: "1.0"
    ---

    # Test Skill

    This is the body content.
    """

    minimal_skill = """
    ---
    name: minimal
    description: Minimal skill.
    ---

    Body.
    """

    no_frontmatter = """
    # No Frontmatter

    Just content.
    """

    invalid_yaml = """
    ---
    name: [invalid
    description: "unclosed
    ---

    Body.
    """

    invalid_name = """
    ---
    name: Invalid_Name!
    description: Has invalid name.
    ---

    Body.
    """

    missing_name = """
    ---
    description: Missing name field.
    ---

    Body.
    """

    allowed_tools_list = """
    ---
    name: tools-list
    description: Allowed tools as list.
    allowed-tools:
      - tool1
      - tool2
      - tool3
    ---

    Body.
    """

    File.write!(Path.join(@fixtures_path, "valid.md"), valid_skill)
    File.write!(Path.join(@fixtures_path, "minimal.md"), minimal_skill)
    File.write!(Path.join(@fixtures_path, "no_frontmatter.md"), no_frontmatter)
    File.write!(Path.join(@fixtures_path, "invalid_yaml.md"), invalid_yaml)
    File.write!(Path.join(@fixtures_path, "invalid_name.md"), invalid_name)
    File.write!(Path.join(@fixtures_path, "missing_name.md"), missing_name)
    File.write!(Path.join(@fixtures_path, "allowed_tools_list.md"), allowed_tools_list)

    on_exit(fn ->
      File.rm_rf!(@fixtures_path)
    end)

    :ok
  end

  describe "load/1" do
    test "loads a valid SKILL.md file" do
      path = Path.join(@fixtures_path, "valid.md")
      assert {:ok, %Spec{} = spec} = Loader.load(path)

      assert spec.name == "test-skill"
      assert spec.description == "A test skill for unit testing."
      assert spec.license == "MIT"
      assert spec.allowed_tools == ["tool_one", "tool_two"]
      assert spec.metadata == %{"author" => "test-author", "version" => "1.0"}
      assert spec.source == {:file, path}
      assert {:inline, body} = spec.body_ref
      assert body =~ "# Test Skill"
    end

    test "loads minimal skill with only required fields" do
      path = Path.join(@fixtures_path, "minimal.md")
      assert {:ok, %Spec{} = spec} = Loader.load(path)

      assert spec.name == "minimal"
      assert spec.description == "Minimal skill."
      assert spec.license == nil
      assert spec.allowed_tools == []
    end

    test "returns error for missing file" do
      assert {:error, _} = Loader.load("/nonexistent/path.md")
    end

    test "returns error for no frontmatter" do
      path = Path.join(@fixtures_path, "no_frontmatter.md")
      assert {:error, %Error.Parse.NoFrontmatter{}} = Loader.load(path)
    end

    test "returns error for invalid YAML" do
      path = Path.join(@fixtures_path, "invalid_yaml.md")
      assert {:error, %Error.Parse.InvalidYaml{}} = Loader.load(path)
    end

    test "returns error for invalid name format" do
      path = Path.join(@fixtures_path, "invalid_name.md")
      assert {:error, %Error.Validation.InvalidName{name: "Invalid_Name!"}} = Loader.load(path)
    end

    test "returns error for missing name" do
      path = Path.join(@fixtures_path, "missing_name.md")
      assert {:error, %Error.Validation.MissingField{field: :name}} = Loader.load(path)
    end

    test "normalizes allowed-tools lists only in lenient mode" do
      path = Path.join(@fixtures_path, "allowed_tools_list.md")

      assert {:error, %Error.Validation.InvalidField{field: :allowed_tools, reason: :invalid_type}} =
               Loader.load(path)

      assert {:ok, %Spec{allowed_tools: tools, diagnostics: diagnostics}} = Loader.load(path, lenient: true)
      assert tools == ["tool1", "tool2", "tool3"]
      assert Enum.any?(diagnostics.warnings, &(&1.type == :invalid_allowed_tools_type))
    end
  end

  describe "load!/1" do
    test "returns spec for valid file" do
      path = Path.join(@fixtures_path, "valid.md")
      assert %Spec{name: "test-skill"} = Loader.load!(path)
    end

    test "raises for invalid file" do
      path = Path.join(@fixtures_path, "no_frontmatter.md")
      assert_raise Error.Parse.NoFrontmatter, fn -> Loader.load!(path) end
    end
  end

  describe "parse/2" do
    test "parses content string" do
      content = """
      ---
      name: inline-skill
      description: Parsed from string.
      ---

      # Inline Body
      """

      assert {:ok, %Spec{name: "inline-skill"}} = Loader.parse(content)
    end

    test "uses provided source path" do
      content = """
      ---
      name: sourced
      description: With source.
      ---

      Body.
      """

      assert {:ok, %Spec{source: {:file, "custom/path.md"}}} = Loader.parse(content, "custom/path.md")
    end
  end

  describe "name validation" do
    test "accepts valid kebab-case names" do
      for name <- ["a", "test", "my-skill", "skill-v2", "a1b2c3", "my-cool-skill-123"] do
        content = """
        ---
        name: #{name}
        description: Test.
        ---

        Body.
        """

        assert {:ok, %Spec{name: ^name}} = Loader.parse(content)
      end
    end

    test "rejects invalid names" do
      invalid_names = [
        "MySkill",
        "my_skill",
        "my skill",
        "-leading-dash",
        "trailing-dash-",
        "double--dash",
        "UPPERCASE"
      ]

      for name <- invalid_names do
        content = """
        ---
        name: #{name}
        description: Test.
        ---

        Body.
        """

        assert {:error, %Error.Validation.InvalidName{}} = Loader.parse(content),
               "Expected #{name} to be invalid"
      end
    end

    test "lenient mode normalizes repeated separators" do
      content = """
      ---
      name: my__bad---skill
      description: Test.
      ---

      Body.
      """

      assert {:ok, %Spec{name: "my-bad-skill", diagnostics: diagnostics}} =
               Loader.parse(content, "inline", lenient: true)

      assert Enum.any?(diagnostics.warnings, &(&1.type == :invalid_name_format))
    end
  end

  describe "field normalization" do
    test "strict mode rejects blank descriptions" do
      content = """
      ---
      name: blank-description
      description: "   "
      ---

      Body.
      """

      assert {:error, %Error.Validation.MissingField{field: :description}} =
               Loader.parse(content)
    end

    test "lenient mode falls back for blank descriptions" do
      content = """
      ---
      name: blank-description
      description: "   "
      ---

      Body.
      """

      assert {:ok, %Spec{description: "No description provided", diagnostics: diagnostics}} =
               Loader.parse(content, "inline", lenient: true)

      assert Enum.any?(diagnostics.warnings, &(&1.type == :blank_description))
    end

    test "normalizes optional fields to their public spec types" do
      content = """
      ---
      name: normalized-fields
      description: Normalizes optional field types.
      license: 123
      version: 456
      tags:
        - one
        - 2
      metadata: invalid
      ---

      Body.
      """

      assert {:ok, %Spec{} = spec} = Loader.parse(content, "inline", lenient: true)

      assert spec.license == nil
      assert spec.vsn == nil
      assert spec.tags == ["one", "2"]
      assert spec.metadata == %{}
      assert Enum.any?(spec.diagnostics.warnings, &(&1.type == :invalid_license))
      assert Enum.any?(spec.diagnostics.warnings, &(&1.type == :invalid_metadata_type))
    end

    test "strict mode rejects overlong descriptions and compatibility" do
      long_description = String.duplicate("d", 1_025)
      long_compatibility = String.duplicate("c", 501)

      assert {:error, %Error.Validation.InvalidField{field: :description, reason: :too_long}} =
               Loader.parse("---\nname: strict-fields\ndescription: #{long_description}\n---\n")

      assert {:error, %Error.Validation.InvalidField{field: :compatibility, reason: :too_long}} =
               Loader.parse("---\nname: strict-fields\ndescription: Valid\ncompatibility: #{long_compatibility}\n---\n")
    end

    test "strict mode requires string metadata keys and values" do
      content = """
      ---
      name: strict-metadata
      description: Valid metadata is interoperable.
      metadata:
        version: 2
      ---
      """

      assert {:error, %Error.Validation.InvalidField{field: :metadata, reason: :invalid_metadata}} =
               Loader.parse(content)

      assert {:ok, %Spec{metadata: %{"version" => "2"}, diagnostics: diagnostics}} =
               Loader.parse(content, "inline", lenient: true)

      assert Enum.any?(diagnostics.warnings, &(&1.type == :invalid_metadata_entries))
    end

    test "strict mode requires optional standard fields to use specification types" do
      assert {:ok, %Spec{license: ""}} =
               Loader.parse("---\nname: empty-license\ndescription: Valid\nlicense: \"\"\n---\n")

      assert {:error, %Error.Validation.InvalidField{field: :license, reason: :invalid_type}} =
               Loader.parse("---\nname: strict-license\ndescription: Valid\nlicense: 123\n---\n")

      assert {:error, %Error.Validation.InvalidField{field: :allowed_tools, reason: :invalid_type}} =
               Loader.parse("---\nname: strict-tools\ndescription: Valid\nallowed-tools: [read, write]\n---\n")
    end

    @tag :tmp_dir
    test "strict mode requires the name to match the parent directory", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "actual-name")
      File.mkdir_p!(skill_dir)
      path = Path.join(skill_dir, "SKILL.md")

      File.write!(path, "---\nname: declared-name\ndescription: Test\n---\n")

      assert {:error,
              %Error.Validation.InvalidField{
                field: :name,
                reason: :directory_name_mismatch
              }} = Loader.load(path)

      assert {:ok, %Spec{diagnostics: diagnostics}} = Loader.load(path, lenient: true)
      assert Enum.any?(diagnostics.warnings, &(&1.type == :directory_name_mismatch))
    end

    @tag :tmp_dir
    test "strict mode resolves a relative SKILL.md path before checking its parent", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "relative-skill")
      File.mkdir_p!(skill_dir)
      skill_file = Path.join(skill_dir, "SKILL.md")
      File.write!(skill_file, "---\nname: relative-skill\ndescription: Test\n---\n")
      relative_path = Path.relative_to(skill_file, File.cwd!())

      assert Path.type(relative_path) == :relative
      assert {:ok, %Spec{name: "relative-skill"}} = Loader.load(relative_path)
    end
  end

  describe "non-binary name" do
    # Regression: build_spec/5 ran the directory-name comparison before
    # validating the name's type, so a YAML scalar like `name: 123` hit
    # String.downcase/1 on an integer and raised instead of producing a
    # validation error (strict) or a fallback name (lenient).
    @non_binary_name """
    ---
    name: 123
    description: Name is not a string.
    ---

    Body.
    """

    test "strict mode returns a validation error without raising" do
      assert {:error, %Error.Validation.MissingField{field: :name}} =
               Loader.parse(@non_binary_name)
    end

    test "lenient mode generates the documented fallback name" do
      assert {:ok, %Spec{name: name, diagnostics: diagnostics}} =
               Loader.parse(@non_binary_name, "inline", lenient: true)

      assert String.starts_with?(name, "unnamed-skill-")
      assert Enum.any?(diagnostics.warnings, &(&1.type == :invalid_name_type))
    end

    test "does not warn about a directory-name mismatch for a non-binary name" do
      assert {:ok, %Spec{diagnostics: diagnostics}} =
               Loader.parse(@non_binary_name, "inline", lenient: true)

      refute Enum.any?(diagnostics.warnings, &(&1.type == :directory_name_mismatch))
    end
  end

  describe "lenient name normalization" do
    test "falls back when normalization cannot produce a valid skill name" do
      content = """
      ---
      name: "!!!"
      description: Invalid name.
      ---

      Body.
      """

      assert {:ok, %Spec{name: name, diagnostics: diagnostics}} =
               Loader.parse(content, "inline", lenient: true)

      assert String.starts_with?(name, "unnamed-skill-")
      assert Enum.any?(diagnostics.warnings, &(&1.type == :invalid_name_format))
    end
  end
end
