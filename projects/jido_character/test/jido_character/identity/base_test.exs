defmodule Jido.Character.Identity.BaseTest do
  use ExUnit.Case, async: true
  alias Jido.Character.Identity.Base

  describe "changeset/2" do
    test "validates required fields" do
      changeset = Base.changeset(%Base{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).unique_id
      assert "can't be blank" in errors_on(changeset).creation_timestamp
      assert "can't be blank" in errors_on(changeset).version
    end

    test "validates character_type inclusion" do
      attrs = %{
        unique_id: UUID.uuid4(),
        creation_timestamp: DateTime.utc_now(),
        version: 1,
        character_type: "invalid_type"
      }

      changeset = Base.changeset(%Base{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).character_type
    end

    test "validates version is greater than 0" do
      attrs = %{
        unique_id: UUID.uuid4(),
        creation_timestamp: DateTime.utc_now(),
        version: 0,
        character_type: "npc"
      }

      changeset = Base.changeset(%Base{}, attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).version
    end

    test "validates tags length" do
      attrs = %{
        unique_id: UUID.uuid4(),
        creation_timestamp: DateTime.utc_now(),
        version: 1,
        character_type: "npc",
        tags: List.duplicate("tag", 21)
      }

      changeset = Base.changeset(%Base{}, attrs)
      refute changeset.valid?
      assert "should have at most 20 item(s)" in errors_on(changeset).tags
    end

    test "creates valid changeset with valid attributes" do
      attrs = %{
        unique_id: UUID.uuid4(),
        creation_timestamp: DateTime.utc_now(),
        version: 1,
        character_type: "npc",
        namespace: "test",
        tags: ["tag1", "tag2"]
      }

      changeset = Base.changeset(%Base{}, attrs)
      assert changeset.valid?
    end
  end

  describe "template/1" do
    test "creates a base template with default values" do
      base = Base.template()
      assert is_binary(base.unique_id)
      assert %DateTime{} = base.creation_timestamp
      assert base.character_type == "npc"
      assert base.version == 1
      assert base.namespace == "default"
      assert base.tags == []
    end

    test "merges provided attributes with defaults" do
      attrs = %{
        character_type: "player",
        namespace: "custom",
        tags: ["custom_tag"]
      }

      base = Base.template(attrs)
      assert is_binary(base.unique_id)
      assert %DateTime{} = base.creation_timestamp
      assert base.character_type == "player"
      assert base.version == 1
      assert base.namespace == "custom"
      assert base.tags == ["custom_tag"]
    end
  end

  # Helper to create a base identity for testing
  def create_test_base do
    Base.template(%{
      unique_id: "test-123",
      character_type: "npc",
      namespace: "test",
      tags: ["initial"]
    })
  end

  describe "update_character_type/2" do
    test "successfully updates to valid character type" do
      base = create_test_base()
      assert {:ok, updated} = Base.update_character_type(base, "player")
      assert updated.character_type == "player"
    end

    test "returns error for invalid character type" do
      base = create_test_base()
      assert {:error, changeset} = Base.update_character_type(base, "invalid")
      assert "is invalid" in errors_on(changeset).character_type
    end
  end

  describe "add_tag/2" do
    test "successfully adds a new tag" do
      base = create_test_base()
      assert {:ok, updated} = Base.add_tag(base, "new-tag")
      assert "new-tag" in updated.tags
    end

    test "returns error when tag already exists" do
      base = create_test_base()
      assert {:error, :tag_exists} = Base.add_tag(base, "initial")
    end
  end

  describe "remove_tag/2" do
    test "successfully removes an existing tag" do
      base = create_test_base()
      assert {:ok, updated} = Base.remove_tag(base, "initial")
      refute "initial" in updated.tags
    end

    test "succeeds even if tag doesn't exist" do
      base = create_test_base()
      assert {:ok, updated} = Base.remove_tag(base, "non-existent")
      assert updated.tags == base.tags
    end
  end

  describe "update_namespace/2" do
    test "successfully updates namespace" do
      base = create_test_base()
      assert {:ok, updated} = Base.update_namespace(base, "new-namespace")
      assert updated.namespace == "new-namespace"
    end
  end

  describe "increment_version/1" do
    test "increments version by 1" do
      base = create_test_base()
      initial_version = base.version
      assert {:ok, updated} = Base.increment_version(base)
      assert updated.version == initial_version + 1
    end
  end

  describe "matches_tags?/2" do
    test "returns true when all tags match" do
      base = create_test_base()
      {:ok, base_with_tags} = Base.add_tag(base, "tag2")
      assert Base.matches_tags?(base_with_tags, ["initial", "tag2"])
    end

    test "returns false when any tag doesn't match" do
      base = create_test_base()
      refute Base.matches_tags?(base, ["initial", "non-existent"])
    end
  end

  # Helper function for changeset error testing
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
