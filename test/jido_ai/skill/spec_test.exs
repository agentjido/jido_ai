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

  describe "validate_runtime/2" do
    test "accepts runtime specs with inline bodies" do
      spec = %Spec{name: "runtime-skill", description: "Runtime skill.", body_ref: {:inline, "Body."}}
      assert Spec.validate_runtime(spec, index: 3) == {:ok, spec}
    end

    test "rejects invalid names, missing descriptions, and non-inline bodies" do
      assert {:error, {:invalid_runtime_skill_spec, 0, %Jido.AI.Skill.Error.Validation.InvalidName{}}} =
               Spec.validate_runtime(%Spec{name: "Bad", description: "Bad.", body_ref: {:inline, "Body."}}, index: 0)

      assert {:error,
              {:invalid_runtime_skill_spec, 1, %Jido.AI.Skill.Error.Validation.MissingField{field: :description}}} =
               Spec.validate_runtime(%Spec{name: "bad", description: "", body_ref: {:inline, "Body."}}, index: 1)

      assert {:error,
              {:invalid_runtime_skill_spec, 2,
               %Jido.AI.Skill.Error.Validation.InvalidField{field: :body_ref, reason: :inline_body_required}}} =
               Spec.validate_runtime(%Spec{name: "bad", description: "Bad.", body_ref: {:file, "/tmp/SKILL.md"}},
                 index: 2
               )
    end

    test "requires runtime specs to have no filesystem source" do
      spec = %Spec{
        name: "runtime-source",
        description: "Runtime source.",
        source: {:file, "/tmp/runtime-source/SKILL.md"},
        body_ref: {:inline, "Body."}
      }

      assert {:error,
              {:invalid_runtime_skill_spec, 0,
               %Jido.AI.Skill.Error.Validation.InvalidField{field: :source, reason: :must_be_nil}}} =
               Spec.validate_runtime(spec, index: 0)
    end

    test "shares strict manifest validation for optional fields" do
      long_description = String.duplicate("d", 1_025)
      long_compatibility = String.duplicate("c", 501)

      cases = [
        {%Spec{name: "runtime", description: long_description, body_ref: {:inline, "Body."}}, :description, :too_long},
        {%Spec{name: "runtime", description: "Runtime.", license: 123, body_ref: {:inline, "Body."}}, :license,
         :invalid_type},
        {%Spec{name: "runtime", description: "Runtime.", compatibility: "", body_ref: {:inline, "Body."}},
         :compatibility, :empty},
        {%Spec{
           name: "runtime",
           description: "Runtime.",
           compatibility: long_compatibility,
           body_ref: {:inline, "Body."}
         }, :compatibility, :too_long},
        {%Spec{name: "runtime", description: "Runtime.", metadata: %{"version" => 2}, body_ref: {:inline, "Body."}},
         :metadata, :invalid_metadata},
        {%Spec{name: "runtime", description: "Runtime.", allowed_tools: [:read], body_ref: {:inline, "Body."}},
         :allowed_tools, :invalid_type}
      ]

      for {spec, field, reason} <- cases do
        assert {:error,
                {:invalid_runtime_skill_spec, 0,
                 %Jido.AI.Skill.Error.Validation.InvalidField{field: ^field, reason: ^reason}}} =
                 Spec.validate_runtime(spec, index: 0)
      end
    end
  end
end
