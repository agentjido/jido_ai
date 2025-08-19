defmodule Jido.CharacterTest do
  use ExUnit.Case, async: false
  doctest Jido.Character

  setup do
    Jido.Character.Persistence.Memory.clear()
    :ok
  end

  describe "new/1" do
    test "creates a new character with generated id" do
      assert {:ok, character} = Jido.Character.new()
      assert is_binary(character.id)
      assert %DateTime{} = character.created_at
      assert %DateTime{} = character.updated_at
      assert character.created_at == character.updated_at
    end

    test "creates a new character with provided id" do
      id = "test-id-123"
      assert {:ok, character} = Jido.Character.new(id)
      assert character.id == id
    end
  end

  describe "get/1" do
    test "retrieves an existing character" do
      {:ok, created} = Jido.Character.new("test-get")
      assert {:ok, retrieved} = Jido.Character.get("test-get")
      assert created.id == retrieved.id
      assert created.created_at == retrieved.created_at
    end

    test "returns error for non-existent character" do
      assert {:error, :not_found} = Jido.Character.get("non-existent")
    end
  end

  describe "update/2" do
    test "updates character attributes" do
      {:ok, character} = Jido.Character.new()
      original_updated_at = character.updated_at

      # Add a small delay to ensure timestamps are different
      Process.sleep(1)

      new_attrs = %{
        identity: %{
          username: "test_user",
          display_name: "Test Character"
        }
      }

      assert {:ok, updated} = Jido.Character.update(character, new_attrs)
      assert updated.identity.username == "test_user"
      assert updated.identity.display_name == "Test Character"
      assert DateTime.compare(updated.updated_at, original_updated_at) == :gt
    end

    test "validates updates" do
      {:ok, character} = Jido.Character.new()

      invalid_attrs = %{
        identity: %{
          # Too long username
          username: String.duplicate("a", 257)
        }
      }

      assert {:error, changeset} = Jido.Character.update(character, invalid_attrs)
      refute changeset.valid?
    end
  end

  describe "delete/1" do
    test "removes an existing character" do
      {:ok, character} = Jido.Character.new()
      assert :ok = Jido.Character.delete(character.id)
      assert {:error, :not_found} = Jido.Character.get(character.id)
    end
  end

  describe "clone/2" do
    test "creates a deep copy with new id" do
      {:ok, original} = Jido.Character.new()

      {:ok, original} =
        Jido.Character.update(original, %{
          identity: %{
            username: "original_user",
            display_name: "Original Character"
          }
        })

      new_id = "cloned-123"
      assert {:ok, cloned} = Jido.Character.clone(original, new_id)
      assert cloned.id == new_id
      assert cloned.identity.username == original.identity.username
      assert cloned.identity.display_name == original.identity.display_name
      assert DateTime.compare(cloned.created_at, original.created_at) == :gt
    end
  end

  describe "validate/1" do
    test "validates valid character" do
      {:ok, character} = Jido.Character.new()
      assert :ok = Jido.Character.validate(character)
    end

    test "returns error for invalid character" do
      character = %Jido.Character{id: nil}
      assert {:error, changeset} = Jido.Character.validate(character)
      refute changeset.valid?
    end
  end

  describe "to_json/1 and from_json/1" do
    test "serializes and deserializes character" do
      {:ok, original} = Jido.Character.new()

      new_attrs = %{
        identity: %{
          username: "json_test_user",
          display_name: "JSON Test Character"
        }
      }

      {:ok, original} = Jido.Character.update(original, new_attrs)

      assert {:ok, json} = Jido.Character.to_json(original)
      assert {:ok, decoded} = Jido.Character.from_json(json)
      assert decoded.id == original.id
      assert decoded.identity.username == original.identity.username
      assert decoded.identity.display_name == original.identity.display_name
    end

    test "handles invalid json" do
      assert {:error, %Jason.DecodeError{}} = Jido.Character.from_json("invalid json")
    end
  end
end
