defmodule Jido.Character.IdentityTest do
  use ExUnit.Case, async: true
  alias Jido.Character.Identity

  setup do
    {:ok, character} = create_character_with_identity()
    %{character: character}
  end

  # Improve the helper function
  defp create_character_with_identity do
    {:ok, character} = Jido.Character.new()

    Identity.update_identity(character, %{
      username: "test_user123",
      display_name: "Test User",
      avatar_url: "https://example.com/avatar.jpg",
      interests: ["coding", "gaming"]
    })
  end

  describe "set_username/2" do
    test "updates the username", %{character: character} do
      {:ok, updated} = Identity.set_username(character, "new_username")
      assert updated.identity.username == "new_username"
    end

    test "validates username format", %{character: character} do
      {:error, changeset} = Identity.set_username(character, "invalid username")
      # Access nested identity errors
      assert errors_on(changeset).identity.username == ["has invalid format"]
    end
  end

  describe "set_display_name/2" do
    test "updates the display name", %{character: character} do
      {:ok, updated} = Identity.set_display_name(character, "New Display Name")
      assert updated.identity.display_name == "New Display Name"
    end
  end

  describe "set_avatar_url/2" do
    test "updates the avatar URL", %{character: character} do
      {:ok, updated} = Identity.set_avatar_url(character, "https://example.com/new_avatar.jpg")
      assert updated.identity.avatar_url == "https://example.com/new_avatar.jpg"
    end
  end

  describe "update_identity/2" do
    test "updates multiple identity fields at once", %{character: character} do
      {:ok, updated} =
        Identity.update_identity(character, %{
          username: "updated_user",
          display_name: "Updated User",
          interests: ["reading", "writing"]
        })

      assert updated.identity.username == "updated_user"
      assert updated.identity.display_name == "Updated User"
      assert updated.identity.interests == ["reading", "writing"]
    end

    test "validates all fields", %{character: character} do
      {:error, changeset} =
        Identity.update_identity(character, %{
          username: "inv@lid",
          display_name: String.duplicate("a", 256),
          interests: List.duplicate("interest", 11)
        })

      errors = errors_on(changeset)
      assert errors.identity.username == ["has invalid format"]
      assert errors.identity.display_name == ["should be at most 255 character(s)"]
      assert errors.identity.interests == ["should have at most 10 item(s)"]
    end
  end

  describe "set_interests/2" do
    test "updates the interests list", %{character: character} do
      {:ok, updated} = Identity.set_interests(character, ["reading", "writing", "arithmetic"])
      assert updated.identity.interests == ["reading", "writing", "arithmetic"]
    end

    test "limits interests to 10 items", %{character: character} do
      {:error, changeset} = Identity.set_interests(character, List.duplicate("interest", 11))
      assert errors_on(changeset).identity.interests == ["should have at most 10 item(s)"]
    end
  end

  describe "add_interest/2" do
    test "adds a new interest", %{character: character} do
      {:ok, updated} = Identity.add_interest(character, "hiking")
      assert "hiking" in updated.identity.interests
    end

    test "doesn't add duplicate interests", %{character: character} do
      {:ok, updated} = Identity.add_interest(character, "coding")
      assert Enum.count(updated.identity.interests) == 2
    end

    test "limits total interests to 10", %{character: character} do
      # First add 8 new interests (plus the 2 existing ones makes 10)
      {:ok, character_with_10} =
        Enum.reduce(1..8, {:ok, character}, fn i, {:ok, char} ->
          Identity.add_interest(char, "interest#{i}")
        end)

      assert Enum.count(character_with_10.identity.interests) == 10

      # Try to add an 11th interest - should return error
      {:error, changeset} = Identity.add_interest(character_with_10, "one_too_many")

      assert errors_on(changeset).identity.interests == ["should have at most 10 item(s)"]
      refute "one_too_many" in character_with_10.identity.interests
    end
  end

  describe "remove_interest/2" do
    test "removes an existing interest", %{character: character} do
      {:ok, updated} = Identity.remove_interest(character, "coding")
      refute "coding" in updated.identity.interests
    end

    test "does nothing for non-existent interest", %{character: character} do
      {:ok, updated} = Identity.remove_interest(character, "non_existent")
      assert updated.identity.interests == character.identity.interests
    end
  end

  describe "get_interests/1" do
    test "returns the list of interests", %{character: character} do
      interests = Identity.get_interests(character)
      assert interests == ["coding", "gaming"]
    end

    test "returns an empty list for character without interests" do
      {:ok, character_without_interests} = Jido.Character.new()
      assert Identity.get_interests(character_without_interests) == []
    end
  end

  # Improve error helper to handle nested changesets
  defp errors_on(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
