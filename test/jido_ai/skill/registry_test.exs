defmodule Jido.AI.Skill.RegistryTest do
  use ExUnit.Case

  alias Jido.AI.Skill.{Error, Registry, Spec}

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

    nested_dir = Path.join(@fixtures_path, "nested")
    File.mkdir_p!(nested_dir)

    File.write!(Path.join(@fixtures_path, "SKILL.md"), skill1)
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

      assert length(Registry.list()) == 2
      assert :ok = Registry.clear()
      assert [] = Registry.list()
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
      file_path = Path.join(@fixtures_path, "SKILL.md")

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
