defmodule Jido.AI.Skill.SpecTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skill.Spec

  describe "struct" do
    test "creates with default values" do
      spec = %Spec{name: "test-skill", description: "A test skill"}

      assert spec.name == "test-skill"
      assert spec.description == "A test skill"
      assert spec.allowed_tools == []
      assert spec.actions == []
      assert spec.plugins == []
      assert spec.tags == []
      assert spec.source == nil
      assert spec.body_ref == nil
    end

    test "creates with all fields" do
      spec = %Spec{
        name: "full-skill",
        description: "A fully specified skill",
        license: "MIT",
        compatibility: "Jido >= 2.0",
        metadata: %{"author" => "test"},
        allowed_tools: ["tool1", "tool2"],
        source: {:module, SomeModule},
        body_ref: {:inline, "# Body"},
        actions: [Action1, Action2],
        plugins: [Plugin1],
        vsn: "1.0.0",
        tags: ["tag1", "tag2"]
      }

      assert spec.license == "MIT"
      assert spec.compatibility == "Jido >= 2.0"
      assert spec.metadata == %{"author" => "test"}
      assert spec.allowed_tools == ["tool1", "tool2"]
      assert spec.source == {:module, SomeModule}
      assert spec.body_ref == {:inline, "# Body"}
      assert spec.actions == [Action1, Action2]
      assert spec.plugins == [Plugin1]
      assert spec.vsn == "1.0.0"
      assert spec.tags == ["tag1", "tag2"]
    end

    test "source can be module or file" do
      module_spec = %Spec{name: "mod", description: "d", source: {:module, MyModule}}
      file_spec = %Spec{name: "file", description: "d", source: {:file, "/path/to/SKILL.md"}}

      assert {:module, MyModule} = module_spec.source
      assert {:file, "/path/to/SKILL.md"} = file_spec.source
    end

    test "body_ref can be inline, file, or nil" do
      inline = %Spec{name: "a", description: "d", body_ref: {:inline, "content"}}
      file = %Spec{name: "b", description: "d", body_ref: {:file, "/path"}}
      none = %Spec{name: "c", description: "d", body_ref: nil}

      assert {:inline, "content"} = inline.body_ref
      assert {:file, "/path"} = file.body_ref
      assert nil == none.body_ref
    end
  end
end
