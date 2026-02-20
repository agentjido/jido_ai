defmodule Jido.AI.Skill.RuntimeContractsTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Skill
  alias Jido.AI.Skill.{Error, Loader, Prompt, Registry, Spec}

  @code_review_skill Path.expand("../../../priv/skills/code-review/SKILL.md", __DIR__)
  @skills_glob Path.expand("../../../priv/skills/**/SKILL.md", __DIR__)

  setup do
    start_supervised!(Registry)
    :ok = Registry.clear()
    :ok
  end

  test "runtime happy path: load, register, resolve, and render" do
    assert {:ok, %Spec{} = spec} = Loader.load(@code_review_skill)
    assert :ok = Registry.register(spec)

    assert {:ok, ^spec} = Registry.lookup("code-review")
    assert %Spec{name: "code-review"} = Skill.manifest("code-review")
    assert Skill.body("code-review") =~ "# Code Review"
    assert "read_file" in Skill.allowed_tools("code-review")

    rendered = Prompt.render(["code-review"], include_body: false)
    assert rendered =~ "## code-review"
    assert rendered =~ "Allowed tools: read_file, grep, git_diff"
  end

  test "validation failure returns structured errors" do
    missing_description = """
    ---
    name: missing-description
    ---

    Body content.
    """

    invalid_name = """
    ---
    name: Invalid_Name
    description: Invalid name format.
    ---

    Body content.
    """

    assert {:error, %Error.Validation.MissingField{field: :description}} =
             Loader.parse(missing_description, "inline_missing_description")

    assert {:error, %Error.Validation.InvalidName{name: "Invalid_Name"}} =
             Loader.parse(invalid_name, "inline_invalid_name")
  end

  test "registry lifecycle supports register, unregister, and clear" do
    spec = %Spec{name: "lifecycle-skill", description: "Registry lifecycle test"}

    assert :ok = Registry.register(spec)
    assert "lifecycle-skill" in Registry.list()

    assert :ok = Registry.unregister("lifecycle-skill")
    assert {:error, %Error.NotFound{name: "lifecycle-skill"}} = Registry.lookup("lifecycle-skill")

    assert :ok = Registry.register(spec)
    assert :ok = Registry.clear()
    assert Registry.list() == []
  end

  test "all shipped skill examples in priv/skills load successfully" do
    paths = Path.wildcard(@skills_glob)
    assert paths != []

    for path <- paths do
      assert {:ok, %Spec{name: name}} = Loader.load(path), "expected valid SKILL.md at #{path}"
      assert is_binary(name) and name != ""
    end
  end
end
