defmodule Jido.AI.Skill.ActivationTest do
  use ExUnit.Case

  alias Jido.AI.Skill.{Activation, Registry, Spec}

  setup do
    start_supervised!(Registry)
    :ok
  end

  describe "activate/1 with Spec" do
    test "activates a skill and returns context" do
      spec = %Spec{
        name: "test-skill",
        description: "A test skill",
        body_ref: {:inline, "Skill body content"},
        source: {:file, "/tmp/skills/test-skill/SKILL.md"}
      }

      assert {:ok, context} = Activation.activate(spec)
      assert context.skill.name == "test-skill"
      assert context.skill_body == "Skill body content"
      assert context.root_dir == "/tmp/skills/test-skill"
      assert context.resources == %{scripts: [], references: [], assets: []}
      refute Map.has_key?(context, :durable)
    end

    test "returns existing context on duplicate activation" do
      spec = %Spec{
        name: "dup-skill",
        description: "Dup",
        body_ref: {:inline, "body"},
        source: {:file, "/tmp/dup/SKILL.md"}
      }

      assert {:ok, ctx1} = Activation.activate(spec)
      assert {:ok, ctx2} = Activation.activate(spec)
      assert ctx1 == ctx2
      assert Activation.list_activated() == ["dup-skill"]
    end

    test "activates skill without source file" do
      spec = %Spec{
        name: "no-source",
        description: "No source",
        body_ref: {:inline, "inline body"},
        source: nil
      }

      assert {:ok, context} = Activation.activate(spec)
      assert context.root_dir == nil
      assert context.resources == %{scripts: [], references: [], assets: []}
    end

    @tag :tmp_dir
    test "returns error when body file cannot be loaded", %{tmp_dir: tmp_dir} do
      missing_body_path = Path.join(tmp_dir, "missing-body.md")

      spec = %Spec{
        name: "missing-body",
        description: "Missing body",
        body_ref: {:file, missing_body_path},
        source: nil
      }

      assert {:error, {:body_load_failed, :enoent}} = Activation.activate(spec)
      refute Activation.activated?("missing-body")
    end
  end

  describe "activate/1 with name" do
    test "returns error for unknown skill name" do
      assert {:error, :skill_not_found} = Activation.activate("nonexistent-skill")
    end
  end

  describe "activate/1 with module" do
    defmodule TestSkillModule do
      def manifest do
        %Spec{
          name: "module-skill",
          description: "From module",
          body_ref: {:inline, "module body"},
          source: {:file, "/tmp/module/SKILL.md"}
        }
      end
    end

    test "activates a skill from module manifest" do
      assert {:ok, context} = Activation.activate(TestSkillModule)
      assert context.skill.name == "module-skill"
      assert context.skill_body == "module body"
    end

    test "returns error for invalid module" do
      assert {:error, :invalid_skill_module} = Activation.activate(String)
    end

    test "returns error when module manifest is not a skill spec" do
      defmodule InvalidManifestModule do
        def manifest, do: %{name: "not-a-spec"}
      end

      assert {:error, :invalid_skill_module} = Activation.activate(InvalidManifestModule)
    end
  end

  describe "activate!/1" do
    test "returns context on success" do
      spec = %Spec{
        name: "bang-skill",
        description: "Bang",
        body_ref: {:inline, "bang"},
        source: nil
      }

      assert %{} = Activation.activate!(spec)
    end

    test "raises on failure" do
      assert_raise RuntimeError, fn ->
        Activation.activate!("nonexistent")
      end
    end
  end

  describe "activate_batch/1" do
    test "activates multiple skills" do
      spec1 = %Spec{
        name: "batch-1",
        description: "B1",
        body_ref: {:inline, "1"},
        source: nil
      }

      spec2 = %Spec{
        name: "batch-2",
        description: "B2",
        body_ref: {:inline, "2"},
        source: nil
      }

      results = Activation.activate_batch([spec1, spec2])

      assert [{:ok, _}, {:ok, _}] = results
      assert Enum.sort(Activation.list_activated()) == ["batch-1", "batch-2"]
    end

    test "returns errors for failed activations" do
      results = Activation.activate_batch(["unknown-1", "unknown-2"])

      assert [{:error, :skill_not_found}, {:error, :skill_not_found}] = results
    end
  end

  describe "list_activated/0" do
    test "returns empty list initially" do
      assert Activation.list_activated() == []
    end

    test "lists activated skill names" do
      spec = %Spec{
        name: "listed",
        description: "Listed",
        body_ref: {:inline, "x"},
        source: nil
      }

      Activation.activate!(spec)
      assert Activation.list_activated() == ["listed"]
    end
  end

  describe "get_context/1" do
    test "returns error when not activated" do
      assert {:error, :not_activated} = Activation.get_context("not-active")
    end

    test "returns context for activated skill" do
      spec = %Spec{
        name: "ctx-skill",
        description: "Ctx",
        body_ref: {:inline, "ctx body"},
        source: nil
      }

      Activation.activate!(spec)
      assert {:ok, context} = Activation.get_context("ctx-skill")
      assert context.skill_body == "ctx body"
    end
  end

  describe "activated?/1" do
    test "returns false when not activated" do
      refute Activation.activated?("never-activated")
    end

    test "returns true when activated" do
      spec = %Spec{
        name: "is-active",
        description: "Active",
        body_ref: {:inline, "a"},
        source: nil
      }

      Activation.activate!(spec)
      assert Activation.activated?("is-active")
    end

    test "does not share same-named activations across sessions" do
      first = %Spec{name: "session-skill", description: "First", body_ref: {:inline, "first"}}
      second = %Spec{name: "session-skill", description: "Second", body_ref: {:inline, "second"}}

      assert {:ok, %{skill_body: "first"}} = Activation.activate(first, session_id: "one")
      assert {:ok, %{skill_body: "second"}} = Activation.activate(second, session_id: "two")

      assert Activation.activated?("session-skill", session_id: "one")
      assert Activation.activated?("session-skill", session_id: "two")
      refute Activation.activated?("session-skill", session_id: "three")
    end
  end
end
