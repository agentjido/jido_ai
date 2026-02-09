defmodule Jido.AI.Skill.LoaderTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skill.{Error, Loader, Spec}

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

    test "parses allowed-tools as list" do
      path = Path.join(@fixtures_path, "allowed_tools_list.md")
      assert {:ok, %Spec{allowed_tools: tools}} = Loader.load(path)
      assert tools == ["tool1", "tool2", "tool3"]
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
  end
end
