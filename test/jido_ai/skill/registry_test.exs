defmodule Jido.AI.Skill.RegistryTest do
  use ExUnit.Case

  alias Jido.AI.Skill.{Registry, Spec, Error}

  @fixtures_path Path.join([__DIR__, "..", "..", "fixtures", "skills", "registry"])

  setup do
    # Start the registry for each test
    start_supervised!(Registry)

    # Create fixtures
    File.mkdir_p!(@fixtures_path)

    skill1 = """
    ---
    name: skill-one
    description: First skill.
    ---

    Body one.
    """

    skill2 = """
    ---
    name: skill-two
    description: Second skill.
    ---

    Body two.
    """

    skill1_dir = Path.join(@fixtures_path, "skill-one")
    nested_dir = Path.join([@fixtures_path, "nested", "skill-two"])
    File.mkdir_p!(skill1_dir)
    File.mkdir_p!(nested_dir)

    File.write!(Path.join(skill1_dir, "SKILL.md"), skill1)
    File.write!(Path.join(nested_dir, "SKILL.md"), skill2)

    on_exit(fn ->
      File.rm_rf!(@fixtures_path)
    end)

    :ok
  end

  describe "register/1" do
    test "registers a skill spec" do
      spec = %Spec{name: "my-skill", description: "Test"}

      assert :ok = Registry.register(spec)
      assert {:ok, ^spec} = Registry.lookup("my-skill")
    end

    test "overwrites existing skill with same name" do
      spec1 = %Spec{name: "same-name", description: "First"}
      spec2 = %Spec{name: "same-name", description: "Second"}

      Registry.register(spec1)
      Registry.register(spec2)

      assert {:ok, %Spec{description: "Second"}} = Registry.lookup("same-name")
    end
  end

  describe "lookup/1" do
    test "returns spec for registered skill" do
      spec = %Spec{name: "lookup-test", description: "Test"}
      Registry.register(spec)

      assert {:ok, ^spec} = Registry.lookup("lookup-test")
    end

    test "returns error for unregistered skill" do
      assert {:error, %Error.NotFound{name: "nonexistent"}} = Registry.lookup("nonexistent")
    end
  end

  describe "list/0" do
    test "returns empty list when no skills registered" do
      assert [] = Registry.list()
    end

    test "returns all registered skill names" do
      Registry.register(%Spec{name: "skill-a", description: "A"})
      Registry.register(%Spec{name: "skill-b", description: "B"})
      Registry.register(%Spec{name: "skill-c", description: "C"})

      names = Registry.list()
      assert length(names) == 3
      assert "skill-a" in names
      assert "skill-b" in names
      assert "skill-c" in names
    end
  end

  describe "all/0" do
    test "returns all registered specs" do
      spec1 = %Spec{name: "all-a", description: "A"}
      spec2 = %Spec{name: "all-b", description: "B"}

      Registry.register(spec1)
      Registry.register(spec2)

      specs = Registry.all()
      assert length(specs) == 2
      assert Enum.any?(specs, &(&1.name == "all-a"))
      assert Enum.any?(specs, &(&1.name == "all-b"))
    end
  end

  describe "unregister/1" do
    test "removes a registered skill" do
      spec = %Spec{name: "to-remove", description: "Test"}
      Registry.register(spec)

      assert {:ok, _} = Registry.lookup("to-remove")
      assert :ok = Registry.unregister("to-remove")
      assert {:error, _} = Registry.lookup("to-remove")
    end

    test "succeeds for non-existent skill" do
      assert :ok = Registry.unregister("never-existed")
    end
  end

  describe "clear/0" do
    test "removes all registered skills" do
      Registry.register(%Spec{name: "clear-a", description: "A"})
      Registry.register(%Spec{name: "clear-b", description: "B"})
      Registry.mark_activated("clear-a", %{skill: "context"})

      assert length(Registry.list()) == 2
      assert Registry.activated?("clear-a")
      assert :ok = Registry.clear()
      assert [] = Registry.list()
      refute Registry.activated?("clear-a")
    end
  end

  describe "activation lifecycle" do
    test "tracks activation state without exposing durable bookkeeping" do
      context = %{skill: %Spec{name: "active-skill", description: "Active"}}

      assert :ok = Registry.mark_activated("active-skill", context)
      assert Registry.activated?("active-skill")
      assert {:ok, ^context} = Registry.get_activation_context("active-skill")

      assert :ok = Registry.mark_durable("active-skill")
      assert Registry.durable?("active-skill")
      assert {:ok, ^context} = Registry.get_activation_context("active-skill")
      assert {:error, :skill_is_durable} = Registry.deactivate("active-skill")

      assert :ok = Registry.unmark_durable("active-skill")
      refute Registry.durable?("active-skill")
      assert :ok = Registry.deactivate("active-skill")
      refute Registry.activated?("active-skill")
      assert {:error, :not_activated} = Registry.get_activation_context("active-skill")
    end

    test "isolates activation state by session" do
      context_a = %{skill: %Spec{name: "shared-skill", description: "Session A"}}
      context_b = %{skill: %Spec{name: "shared-skill", description: "Session B"}}

      assert :ok = Registry.mark_activated("shared-skill", context_a, session_id: "session-a")
      assert Registry.activated?("shared-skill", session_id: "session-a")
      refute Registry.activated?("shared-skill", session_id: "session-b")

      assert :ok = Registry.mark_activated("shared-skill", context_b, session_id: "session-b")
      assert {:ok, ^context_a} = Registry.get_activation_context("shared-skill", session_id: "session-a")
      assert {:ok, ^context_b} = Registry.get_activation_context("shared-skill", session_id: "session-b")
      assert Registry.list_activated(session_id: "session-a") == ["shared-skill"]
      assert Registry.list_activated(session_id: "session-b") == ["shared-skill"]
    end

    test "clears one session without affecting another" do
      context = %{skill: %Spec{name: "session-cleanup", description: "Cleanup"}}

      assert :ok = Registry.mark_activated("session-cleanup", context, session_id: "session-a")
      assert :ok = Registry.mark_durable("session-cleanup", session_id: "session-a")
      assert :ok = Registry.mark_activated("session-cleanup", context, session_id: "session-b")

      assert :ok = Registry.clear_activations(session_id: "session-a")
      refute Registry.activated?("session-cleanup", session_id: "session-a")
      assert Registry.activated?("session-cleanup", session_id: "session-b")
    end
  end

  describe "load_from_paths/1" do
    test "loads skills from directory" do
      assert {:ok, count} = Registry.load_from_paths([@fixtures_path])
      assert count == 2

      assert {:ok, %Spec{name: "skill-one"}} = Registry.lookup("skill-one")
      assert {:ok, %Spec{name: "skill-two"}} = Registry.lookup("skill-two")
    end

    test "loads skill from direct file path" do
      file_path = Path.join([@fixtures_path, "skill-one", "SKILL.md"])

      assert {:ok, 1} = Registry.load_from_paths([file_path])
      assert {:ok, %Spec{name: "skill-one"}} = Registry.lookup("skill-one")
    end

    test "handles empty paths list" do
      assert {:ok, 0} = Registry.load_from_paths([])
    end

    test "ignores non-existent paths" do
      assert {:ok, 0} = Registry.load_from_paths(["/nonexistent/path"])
    end
  end
end
