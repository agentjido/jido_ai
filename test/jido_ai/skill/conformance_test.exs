defmodule Jido.AI.Skill.ConformanceTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skill.{Diagnostics, Error, Loader, Spec}

  @fixture Path.expand("../../fixtures/agent_skills_conformance/spec-valid/SKILL.md", __DIR__)

  describe "specification fixture" do
    test "loads all standard fields and namespaced Jido metadata" do
      assert {:ok, %Spec{} = spec} = Loader.load(@fixture)
      assert spec.name == "spec-valid"
      assert spec.allowed_tools == ["read_file", "grep"]
      assert spec.tags == ["review", "security"]
      assert spec.vsn == "1.0.0"
      assert spec.metadata["jido_ai.tags"] == "review security"
    end
  end

  describe "document boundaries" do
    test "accepts an empty body and a closing delimiter at EOF" do
      content = "---\nname: empty-body\ndescription: Empty body is valid.\n---"

      assert {:ok, %Spec{body_ref: {:inline, ""}}} = Loader.parse(content)
    end

    test "accepts CRLF input" do
      content = "---\r\nname: crlf\r\ndescription: CRLF input is valid.\r\n---\r\nBody.\r\n"

      assert {:ok, %Spec{body_ref: {:inline, "Body."}}} = Loader.parse(content)
    end

    test "accepts an optional UTF-8 BOM" do
      content = <<0xEF, 0xBB, 0xBF>> <> "---\nname: bom\ndescription: BOM input is valid.\n---\n"

      assert {:ok, %Spec{name: "bom"}} = Loader.parse(content)
    end

    test "returns structured errors for YAML scalars and sequences" do
      for content <- ["---\nhello\n---\n", "---\n- hello\n---\n"] do
        assert {:error,
                %Error.Parse.InvalidYaml{
                  reason: :frontmatter_must_be_mapping
                }} = Loader.parse(content)
      end
    end

    test "returns a structured error for malformed YAML" do
      assert {:error, %Error.Parse.InvalidYaml{}} =
               Loader.parse("---\nname: [broken\ndescription: Invalid\n---\n")
    end
  end

  describe "strict schema" do
    test "accepts names at the exact length boundaries" do
      one = "a"
      sixty_four = String.duplicate("a", 64)

      assert {:ok, %Spec{name: ^one}} = Loader.parse(skill(one))
      assert {:ok, %Spec{name: ^sixty_four}} = Loader.parse(skill(sixty_four))
    end

    test "rejects names over 64 characters and invalid hyphen forms" do
      invalid_names = [String.duplicate("a", 65), "-leading", "trailing-", "two--hyphens", "UPPER"]

      for name <- invalid_names do
        assert {:error, %Error.Validation.InvalidName{name: ^name}} = Loader.parse(skill(name))
      end
    end

    test "rejects unsupported top-level fields" do
      content = """
      ---
      name: portable
      description: Uses only portable fields.
      tags: [review]
      version: "1.0"
      ---
      """

      assert {:error,
              %Error.Validation.InvalidField{
                field: :frontmatter,
                reason: :unsupported_top_level_fields,
                value: ["tags", "version"]
              }} = Loader.parse(content)

      assert {:ok, %Spec{diagnostics: diagnostics}} = Loader.parse(content, "inline", lenient: true)
      assert Enum.any?(diagnostics.warnings, &(&1.type == :unsupported_top_level_fields))
    end

    test "requires string metadata keys and values" do
      content = "---\nname: typed-metadata\ndescription: Metadata must be strings.\nmetadata:\n  version: 2\n---\n"

      assert {:error,
              %Error.Validation.InvalidField{
                field: :metadata,
                reason: :invalid_metadata
              }} = Loader.parse(content)
    end

    test "requires allowed-tools to be a space-separated string" do
      content = "---\nname: typed-tools\ndescription: Tools must be a string.\nallowed-tools: [read, grep]\n---\n"

      assert {:error,
              %Error.Validation.InvalidField{
                field: :allowed_tools,
                reason: :invalid_type
              }} = Loader.parse(content)
    end
  end

  describe "filesystem layout" do
    @tag :tmp_dir
    test "requires the exact SKILL.md filename", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "exact-name")
      File.mkdir_p!(skill_dir)
      path = Path.join(skill_dir, "skill.md")
      File.write!(path, skill("exact-name"))

      assert {:error,
              %Error.Validation.InvalidField{
                field: :file_name,
                reason: :invalid_skill_filename
              }} = Loader.load(path)
    end

    @tag :tmp_dir
    test "requires the parent directory to match the declared name", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "actual-name")
      File.mkdir_p!(skill_dir)
      path = Path.join(skill_dir, "SKILL.md")
      File.write!(path, skill("declared-name"))

      assert {:error,
              %Error.Validation.InvalidField{
                field: :name,
                reason: :directory_name_mismatch
              }} = Loader.load(path)
    end

    test "keeps in-memory parsing independent of the source filename" do
      assert {:ok, %Spec{name: "in-memory"}} =
               Loader.parse(skill("in-memory"), "/not/a/matching/file.md")
    end
  end

  describe "diagnostic preservation" do
    @tag :tmp_dir
    test "returns earlier diagnostics when a later strict validation fails", %{tmp_dir: tmp_dir} do
      diagnostics =
        Diagnostics.new()
        |> Diagnostics.add_warning(Diagnostics.Warning.new(:earlier_warning, "Keep this warning"))

      skill_dir = Path.join(tmp_dir, "diagnostics")
      File.mkdir_p!(skill_dir)
      path = Path.join(skill_dir, "SKILL.md")
      File.write!(path, skill("wrong-name"))

      assert {:error, %Error.Validation.InvalidField{}, returned} =
               Loader.load_with_diagnostics(path, lenient: false, diagnostics: diagnostics)

      assert Enum.any?(returned.warnings, &(&1.type == :earlier_warning))
      assert Diagnostics.error_count(returned) == 1
    end
  end

  defp skill(name) do
    "---\nname: #{name}\ndescription: A valid skill description.\n---\n"
  end
end
