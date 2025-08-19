defmodule Jido.Dialogue.CharacterRegistryTest do
  use ExUnit.Case
  alias Jido.Dialogue.{CharacterRegistry, TestHelper}

  setup do
    TestHelper.start_supervised_app()
    on_exit(fn -> TestHelper.stop_supervised_app() end)
    :ok
  end

  test "register_character/3 registers a character with a conversation" do
    conversation_id = "test-convo-" <> UUID.uuid4()
    character_name = "TechnicalGuide"
    config = %{role: "A helpful technical guide"}

    assert :ok = CharacterRegistry.register_character(conversation_id, character_name, config)
  end

  test "register_character/3 returns error when character already exists in conversation" do
    conversation_id = "test-convo-" <> UUID.uuid4()
    character_name = "TechnicalGuide"
    config = %{role: "A helpful technical guide"}

    :ok = CharacterRegistry.register_character(conversation_id, character_name, config)

    assert {:error, :already_exists} =
             CharacterRegistry.register_character(conversation_id, character_name, config)
  end

  test "get_conversation_characters/1 returns all characters in a conversation" do
    conversation_id = "test-convo-" <> UUID.uuid4()

    CharacterRegistry.register_character(
      conversation_id,
      "Guide1",
      %{role: "guide"}
    )

    CharacterRegistry.register_character(
      conversation_id,
      "Guide2",
      %{role: "guide"}
    )

    assert {:ok, characters} = CharacterRegistry.get_conversation_characters(conversation_id)
    assert map_size(characters) == 2
    assert Map.has_key?(characters, "Guide1")
    assert Map.has_key?(characters, "Guide2")
  end

  test "get_conversation_characters/1 returns empty map for non-existent conversation" do
    assert {:ok, %{}} = CharacterRegistry.get_conversation_characters("missing-convo")
  end
end
