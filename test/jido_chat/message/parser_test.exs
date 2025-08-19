defmodule Jido.Chat.Message.ParserTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.Message.Parser

  describe "parse/1" do
    test "parses content with mentions" do
      content = "Hello @alice and @bob! How are you @charlie?"

      {:ok, _parsed_content, mentions} = Parser.parse(content)

      assert length(mentions) == 3
      assert "alice" in mentions
      assert "bob" in mentions
      assert "charlie" in mentions
    end

    test "parses content with no mentions" do
      content = "Hello everyone! How are you all doing today?"

      {:ok, _parsed_content, mentions} = Parser.parse(content)

      assert mentions == []
    end

    test "handles complex mentions with special characters" do
      content = "Hello @alice.smith and @bob_jones! Have you met @charlie-brown?"

      {:ok, _parsed_content, mentions} = Parser.parse(content)

      # Note: The current implementation only captures alphanumeric and underscore characters
      # So the mentions will be truncated at special characters
      assert "alice" in mentions
      assert "bob_jones" in mentions
      assert "charlie" in mentions
    end

    test "handles repeated mentions" do
      content = "Hey @alice, I think @bob and @alice should talk to @bob"

      {:ok, _parsed_content, mentions} = Parser.parse(content)

      # All mentions are captured, including duplicates
      assert length(mentions) == 4
      assert Enum.count(mentions, &(&1 == "alice")) == 2
      assert Enum.count(mentions, &(&1 == "bob")) == 2
    end

    test "returns error for invalid input" do
      result = Parser.parse(nil)
      assert result == {:error, :invalid_input}
    end
  end

  describe "parse_mentions/2" do
    test "creates mention structs with position information" do
      content = "Hello @alice and @bob!"

      participants = %{
        "user1" => "alice",
        "user2" => "bob"
      }

      {:ok, mentions} = Parser.parse_mentions(content, participants)

      assert length(mentions) == 2

      alice_mention = Enum.find(mentions, fn m -> m.display_name == "alice" end)
      assert alice_mention.participant_id == "user1"
      assert alice_mention.offset == 6
      assert alice_mention.length == 5

      bob_mention = Enum.find(mentions, fn m -> m.display_name == "bob" end)
      assert bob_mention.participant_id == "user2"
      assert bob_mention.offset == 17
      assert bob_mention.length == 3
    end

    test "handles case insensitive matching" do
      content = "Hello @ALICE and @Bob!"

      participants = %{
        "user1" => "alice",
        "user2" => "bob"
      }

      {:ok, mentions} = Parser.parse_mentions(content, participants)

      assert length(mentions) == 2

      alice_mention = Enum.find(mentions, fn m -> m.display_name == "alice" end)
      assert alice_mention.participant_id == "user1"

      bob_mention = Enum.find(mentions, fn m -> m.display_name == "bob" end)
      assert bob_mention.participant_id == "user2"
    end

    test "ignores mentions that don't match participants" do
      content = "Hello @alice, @bob, and @charlie!"

      participants = %{
        "user1" => "alice",
        "user2" => "bob"
      }

      {:ok, mentions} = Parser.parse_mentions(content, participants)

      assert length(mentions) == 2
      assert Enum.any?(mentions, fn m -> m.display_name == "alice" end)
      assert Enum.any?(mentions, fn m -> m.display_name == "bob" end)
      refute Enum.any?(mentions, fn m -> m.display_name == "charlie" end)
    end

    test "handles content with no mentions" do
      content = "Hello everyone! How are you all doing today?"

      participants = %{
        "user1" => "alice",
        "user2" => "bob"
      }

      {:ok, mentions} = Parser.parse_mentions(content, participants)

      assert mentions == []
    end

    test "handles content with no matching mentions" do
      content = "Hello @charlie and @dave!"

      participants = %{
        "user1" => "alice",
        "user2" => "bob"
      }

      {:ok, mentions} = Parser.parse_mentions(content, participants)

      assert mentions == []
    end

    test "returns error for invalid input" do
      result = Parser.parse_mentions(nil, %{})
      assert result == {:error, :invalid_input}

      result = Parser.parse_mentions("Hello", nil)
      assert result == {:error, :invalid_input}
    end
  end
end
