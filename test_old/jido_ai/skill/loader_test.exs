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

    for {directory, content} <- [
          {"test-skill", valid_skill},
          {"minimal", minimal_skill},
          {"no-frontmatter", no_frontmatter},
          {"invalid-yaml", invalid_yaml},
          {"invalid-name", invalid_name},
          {"missing-name", missing_name},
          {"tools-list", allowed_tools_list}
        ] do
      skill_dir = Path.join(@fixtures_path, directory)
      File.mkdir_p!(skill_dir)
      File.write!(Path.join(skill_dir, "SKILL.md"), content)
    end

    on_exit(fn ->
      File.rm_rf!(@fixtures_path)
    end)

    :ok
  end

  describe "load/1" do
    test "loads a valid SKILL.md file" do
      path = fixture("test-skill")
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
      path = fixture("minimal")
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
      path = fixture("no-frontmatter")
      assert {:error, %Error.Parse.NoFrontmatter{}} = Loader.load(path)
    end

    test "returns error for invalid YAML" do
      path = fixture("invalid-yaml")
      assert {:error, %Error.Parse.InvalidYaml{}} = Loader.load(path)
    end

    test "returns error for invalid name format" do
      path = fixture("invalid-name")
      assert {:error, %Error.Validation.InvalidName{name: "Invalid_Name!"}} = Loader.load(path)
    end

    test "returns error for missing name" do
      path = fixture("missing-name")
      assert {:error, %Error.Validation.MissingField{field: :name}} = Loader.load(path)
    end

    test "normalizes allowed-tools lists only in lenient mode" do
      path = fixture("tools-list")

      assert {:error, %Error.Validation.InvalidField{field: :allowed_tools, reason: :invalid_type}} =
               Loader.load(path)

      assert {:ok, %Spec{allowed_tools: tools, diagnostics: diagnostics}} = Loader.load(path, lenient: true)
      assert tools == ["tool1", "tool2", "tool3"]
      assert Enum.any?(diagnostics.warnings, &(&1.type == :invalid_allowed_tools_type))
    end
  end

  describe "load!/1" do
    test "returns spec for valid file" do
      path = fixture("test-skill")
      assert %Spec{name: "test-skill"} = Loader.load!(path)
    end

    test "raises for invalid file" do
      path = fixture("no-frontmatter")
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

    test "rejects oversized inline content before parsing" do
      content = String.duplicate("x", Spec.max_body_bytes() + 1)

      assert {:error, {:skill_file_too_large, size, limit}} = Loader.parse(content)
      assert size == Spec.max_body_bytes() + 1
      assert limit == Spec.max_body_bytes()
    end

    test "lenient parsing returns diagnostics for missing and invalid frontmatter" do
      assert {:ok, %Spec{} = missing} =
               Loader.parse("Body without frontmatter", "inline", lenient: true)

      assert Enum.any?(missing.diagnostics.errors, &match?(%Error.Parse.NoFrontmatter{}, &1))

      invalid = "---\nname: [invalid\n---\nBody"
      assert {:ok, %Spec{} = parsed} = Loader.parse(invalid, "inline", lenient: true)
      assert Enum.any?(parsed.diagnostics.errors, &match?(%Error.Parse.InvalidYaml{}, &1))
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

    test "lenient mode omits unsupported and invalid optional fields" do
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
      assert spec.tags == []
      assert spec.metadata == %{}
      assert Enum.any?(spec.diagnostics.warnings, &(&1.type == :invalid_license))
      assert Enum.any?(spec.diagnostics.warnings, &(&1.type == :invalid_metadata_type))
      assert Enum.any?(spec.diagnostics.warnings, &(&1.type == :unsupported_top_level_fields))
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

    test "lenient mode truncates long names and descriptions" do
      long_name = String.duplicate("a", 70)
      long_description = String.duplicate("d", 1_030)

      content =
        "---\nname: #{long_name}\ndescription: #{long_description}\n---\nBody"

      assert {:ok, %Spec{} = spec} = Loader.parse(content, "inline", lenient: true)
      assert String.length(spec.name) == 64
      assert String.length(spec.description) == 1_024
      assert Enum.any?(spec.diagnostics.warnings, &(&1.type == :name_too_long))
      assert Enum.any?(spec.diagnostics.warnings, &(&1.type == :description_too_long))
    end

    test "lenient mode handles invalid description, compatibility, and allowed-tools types" do
      content = """
      ---
      name: unusual-fields
      description: 123
      compatibility: [jido, v3]
      allowed-tools: 42
      ---
      Body
      """

      assert {:ok, %Spec{} = spec} = Loader.parse(content, "inline", lenient: true)
      assert spec.description == "No description provided"
      assert spec.compatibility == nil
      assert spec.allowed_tools == []
      assert Enum.any?(spec.diagnostics.warnings, &(&1.type == :invalid_description_type))
      assert Enum.any?(spec.diagnostics.warnings, &(&1.type == :invalid_compatibility))
      assert Enum.any?(spec.diagnostics.warnings, &(&1.type == :invalid_allowed_tools_type))

      assert {:error, %Error.Validation.MissingField{field: :description}} =
               Loader.parse(String.replace(content, "lenient", "strict"))
    end

    test "empty and long compatibility values follow strict and lenient rules" do
      empty = "---\nname: empty-compat\ndescription: Valid\ncompatibility: \"\"\n---\n"
      assert {:error, %Error.Validation.InvalidField{field: :compatibility, reason: :empty}} = Loader.parse(empty)

      assert {:ok, %Spec{compatibility: nil, diagnostics: empty_diagnostics}} =
               Loader.parse(empty, "inline", lenient: true)

      assert Enum.any?(empty_diagnostics.warnings, &(&1.type == :invalid_compatibility))

      long = String.duplicate("c", 501)
      content = "---\nname: long-compat\ndescription: Valid\ncompatibility: #{long}\n---\n"

      assert {:ok, %Spec{compatibility: compatibility, diagnostics: diagnostics}} =
               Loader.parse(content, "inline", lenient: true)

      assert String.length(compatibility) == 500
      assert Enum.any?(diagnostics.warnings, &(&1.type == :compatibility_too_long))
    end

    test "strict mode rejects scalar metadata and lenient mode normalizes unusual metadata values" do
      strict = "---\nname: scalar-metadata\ndescription: Valid\nmetadata: invalid\n---\n"

      assert {:error, %Error.Validation.InvalidField{field: :metadata, reason: :invalid_type}} =
               Loader.parse(strict)

      lenient = """
      ---
      name: normalized-metadata
      description: Valid
      metadata:
        number: 7
        list: [one, two]
      ---
      """

      assert {:ok, %Spec{metadata: metadata}} = Loader.parse(lenient, "inline", lenient: true)
      assert metadata["number"] == "7"
      assert metadata["list"] == ~s(["one", "two"])
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

  describe "skill file size limits" do
    @tag :tmp_dir
    test "rejects an oversized file before parsing it", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "large-file")
      File.mkdir_p!(skill_dir)
      path = Path.join(skill_dir, "SKILL.md")
      File.write!(path, String.duplicate("x", Spec.max_body_bytes() + 1))

      assert {:error, {:skill_file_too_large, size, limit}} = Loader.load(path)
      assert size > limit
      assert limit == Spec.max_body_bytes()
    end

    @tag :tmp_dir
    test "bounded reads accept empty regular files and reject directories", %{tmp_dir: tmp_dir} do
      empty = Path.join(tmp_dir, "empty")
      File.write!(empty, "")

      assert {:ok, ""} = Loader.read_file(empty)
      assert {:error, :unsafe_skill_file} = Loader.read_file(tmp_dir)
    end

    @tag :tmp_dir
    test "load reports invalid filenames in strict mode and warnings in lenient mode", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "skill.txt")
      File.write!(path, "---\nname: #{Path.basename(tmp_dir)}\ndescription: Valid\n---\n")

      assert {:error, %Error.Validation.InvalidField{reason: :invalid_skill_filename}} = Loader.load(path)

      assert {:ok, %Spec{diagnostics: diagnostics}} = Loader.load(path, lenient: true)
      assert Enum.any?(diagnostics.warnings, &(&1.type == :invalid_skill_filename))
    end
  end

  defp fixture(directory), do: Path.join([@fixtures_path, directory, "SKILL.md"])
end
