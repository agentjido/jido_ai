defmodule Jido.AI.SkillTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Skill
  alias Jido.AI.Skill.{Spec, Registry}

  # Test module-based skill
  defmodule TestSkill do
    use Jido.AI.Skill,
      name: "test-skill",
      description: "A test skill for unit testing.",
      license: "MIT",
      compatibility: "Jido >= 2.0",
      metadata: %{"author" => "test"},
      allowed_tools: ~w(tool1 tool2),
      actions: [SomeAction],
      plugins: [SomePlugin],
      vsn: "1.0.0",
      tags: ["test", "example"],
      body: """
      # Test Skill

      This is the body content.

      ## Usage
      Use this skill for testing.
      """
  end

  defmodule MinimalSkill do
    use Jido.AI.Skill,
      name: "minimal-skill",
      description: "Minimal required fields only."
  end

  @fixtures_path Path.join([__DIR__, "fixtures", "skills"])

  setup do
    start_supervised!(Registry)

    # Create body file fixture
    File.mkdir_p!(@fixtures_path)
    File.write!(Path.join(@fixtures_path, "body.md"), "# Body from file\n\nContent here.")

    on_exit(fn ->
      File.rm_rf!(@fixtures_path)
    end)

    :ok
  end

  describe "module-based skill" do
    test "manifest/0 returns spec" do
      spec = TestSkill.manifest()

      assert %Spec{} = spec
      assert spec.name == "test-skill"
      assert spec.description == "A test skill for unit testing."
      assert spec.license == "MIT"
      assert spec.compatibility == "Jido >= 2.0"
      assert spec.metadata == %{"author" => "test"}
      assert spec.allowed_tools == ["tool1", "tool2"]
      assert spec.source == {:module, TestSkill}
      assert spec.actions == [SomeAction]
      assert spec.plugins == [SomePlugin]
      assert spec.vsn == "1.0.0"
      assert spec.tags == ["test", "example"]
    end

    test "body/0 returns body content" do
      body = TestSkill.body()

      assert body =~ "# Test Skill"
      assert body =~ "This is the body content."
    end

    test "allowed_tools/0 returns tools list" do
      assert TestSkill.allowed_tools() == ["tool1", "tool2"]
    end

    test "actions/0 returns actions list" do
      assert TestSkill.actions() == [SomeAction]
    end

    test "plugins/0 returns plugins list" do
      assert TestSkill.plugins() == [SomePlugin]
    end

    test "minimal skill has defaults" do
      spec = MinimalSkill.manifest()

      assert spec.name == "minimal-skill"
      assert spec.description == "Minimal required fields only."
      assert spec.license == nil
      assert spec.allowed_tools == []
      assert spec.actions == []
      assert spec.plugins == []
      assert spec.tags == []

      assert MinimalSkill.body() == ""
    end
  end

  describe "Skill.manifest/1" do
    test "with module returns spec" do
      spec = Skill.manifest(TestSkill)
      assert %Spec{name: "test-skill"} = spec
    end

    test "with spec returns same spec" do
      spec = %Spec{name: "direct", description: "Direct spec"}
      assert ^spec = Skill.manifest(spec)
    end

    test "with string name looks up in registry" do
      Registry.register(%Spec{name: "registered", description: "From registry"})

      spec = Skill.manifest("registered")
      assert %Spec{name: "registered"} = spec
    end

    test "with unregistered name raises" do
      assert_raise Jido.AI.Skill.Error.NotFound, fn ->
        Skill.manifest("not-registered")
      end
    end
  end

  describe "Skill.body/1" do
    test "with module returns body" do
      assert Skill.body(TestSkill) =~ "# Test Skill"
    end

    test "with inline spec returns content" do
      spec = %Spec{name: "a", description: "b", body_ref: {:inline, "Inline content"}}
      assert Skill.body(spec) == "Inline content"
    end

    test "with nil body_ref returns empty string" do
      spec = %Spec{name: "a", description: "b", body_ref: nil}
      assert Skill.body(spec) == ""
    end

    test "with file body_ref reads from file" do
      body_path = Path.join(@fixtures_path, "body.md")
      spec = %Spec{name: "a", description: "b", body_ref: {:file, body_path}}
      assert Skill.body(spec) == "# Body from file\n\nContent here."
    end
  end

  describe "Skill.allowed_tools/1" do
    test "with module returns tools" do
      assert Skill.allowed_tools(TestSkill) == ["tool1", "tool2"]
    end

    test "with spec returns tools" do
      spec = %Spec{name: "a", description: "b", allowed_tools: ["x", "y"]}
      assert Skill.allowed_tools(spec) == ["x", "y"]
    end
  end

  describe "Skill.actions/1" do
    test "with module returns actions" do
      assert Skill.actions(TestSkill) == [SomeAction]
    end

    test "with spec returns actions" do
      spec = %Spec{name: "a", description: "b", actions: [Action1, Action2]}
      assert Skill.actions(spec) == [Action1, Action2]
    end
  end

  describe "Skill.plugins/1" do
    test "with module returns plugins" do
      assert Skill.plugins(TestSkill) == [SomePlugin]
    end

    test "with spec returns plugins" do
      spec = %Spec{name: "a", description: "b", plugins: [Plugin1, Plugin2]}
      assert Skill.plugins(spec) == [Plugin1, Plugin2]
    end
  end

  describe "Skill.resolve/1" do
    test "resolves module to spec" do
      assert {:ok, %Spec{name: "test-skill"}} = Skill.resolve(TestSkill)
    end

    test "resolves spec to itself" do
      spec = %Spec{name: "a", description: "b"}
      assert {:ok, ^spec} = Skill.resolve(spec)
    end

    test "resolves string name from registry" do
      Registry.register(%Spec{name: "resolvable", description: "c"})
      assert {:ok, %Spec{name: "resolvable"}} = Skill.resolve("resolvable")
    end

    test "returns error for unknown module" do
      assert {:error, _} = Skill.resolve(NonExistentModule)
    end

    test "returns error for unregistered name" do
      assert {:error, _} = Skill.resolve("not-found")
    end
  end

  describe "compile-time validation" do
    test "raises on invalid name format" do
      assert_raise ArgumentError, ~r/Invalid skill name/, fn ->
        defmodule InvalidNameSkill do
          use Jido.AI.Skill,
            name: "Invalid_Name!",
            description: "Test"
        end
      end
    end

    test "raises on empty description" do
      assert_raise ArgumentError, ~r/Invalid skill description/, fn ->
        defmodule EmptyDescSkill do
          use Jido.AI.Skill,
            name: "valid-name",
            description: ""
        end
      end
    end

    test "raises when both body and body_file specified" do
      assert_raise ArgumentError, ~r/Cannot specify both/, fn ->
        defmodule BothBodySkill do
          use Jido.AI.Skill,
            name: "both-body",
            description: "Test",
            body: "inline",
            body_file: "file.md"
        end
      end
    end
  end

  describe "allowed_tools normalization" do
    test "accepts list of strings" do
      defmodule ListToolsSkill do
        use Jido.AI.Skill,
          name: "list-tools",
          description: "Test",
          allowed_tools: ["a", "b", "c"]
      end

      assert ListToolsSkill.allowed_tools() == ["a", "b", "c"]
    end

    test "accepts sigil list" do
      defmodule SigilToolsSkill do
        use Jido.AI.Skill,
          name: "sigil-tools",
          description: "Test",
          allowed_tools: ~w(x y z)
      end

      assert SigilToolsSkill.allowed_tools() == ["x", "y", "z"]
    end

    test "accepts space-delimited string" do
      defmodule StringToolsSkill do
        use Jido.AI.Skill,
          name: "string-tools",
          description: "Test",
          allowed_tools: "one two three"
      end

      assert StringToolsSkill.allowed_tools() == ["one", "two", "three"]
    end
  end

  describe "body_file skill" do
    test "reads body from file using spec body_ref" do
      body_path = Path.join(@fixtures_path, "body.md")
      spec = %Spec{name: "file-body", description: "test", body_ref: {:file, body_path}}

      assert Skill.body(spec) == "# Body from file\n\nContent here."
    end
  end
end
