defmodule Jido.Character.Identity.StyleTest do
  use ExUnit.Case, async: true
  alias Jido.Character.Identity.Style

  describe "changeset/2" do
    test "validates required fields" do
      changeset = Style.changeset(%Style{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).formality_level
      assert "can't be blank" in errors_on(changeset).emoji_usage
      assert "can't be blank" in errors_on(changeset).response_length
    end

    test "validates formality level inclusion" do
      attrs = %{
        formality_level: "invalid",
        emoji_usage: "minimal",
        response_length: "balanced"
      }

      changeset = Style.changeset(%Style{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).formality_level
    end

    test "validates emoji usage inclusion" do
      attrs = %{
        formality_level: "neutral",
        emoji_usage: "invalid",
        response_length: "balanced"
      }

      changeset = Style.changeset(%Style{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).emoji_usage
    end

    test "validates response length inclusion" do
      attrs = %{
        formality_level: "neutral",
        emoji_usage: "minimal",
        response_length: "invalid"
      }

      changeset = Style.changeset(%Style{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).response_length
    end

    test "validates personality traits length" do
      attrs = %{
        formality_level: "neutral",
        emoji_usage: "minimal",
        response_length: "balanced",
        personality_traits: List.duplicate("trait", 11)
      }

      changeset = Style.changeset(%Style{}, attrs)
      refute changeset.valid?
      assert "should have at most 10 item(s)" in errors_on(changeset).personality_traits
    end

    test "validates custom rules length" do
      attrs = %{
        formality_level: "neutral",
        emoji_usage: "minimal",
        response_length: "balanced",
        custom_rules: List.duplicate("rule", 21)
      }

      changeset = Style.changeset(%Style{}, attrs)
      refute changeset.valid?
      assert "should have at most 20 item(s)" in errors_on(changeset).custom_rules
    end

    test "creates valid changeset with valid attributes" do
      attrs = %{
        language_style: "friendly",
        formality_level: "casual",
        emoji_usage: "moderate",
        response_length: "detailed",
        interaction_style: "engaging",
        vocabulary_level: "intermediate",
        personality_traits: ["helpful", "patient"],
        custom_rules: ["always greet", "use positive language"]
      }

      changeset = Style.changeset(%Style{}, attrs)
      assert changeset.valid?
    end

    test "accepts all valid formality levels" do
      Enum.each(["casual", "neutral", "formal", "professional"], fn level ->
        attrs = %{
          formality_level: level,
          emoji_usage: "minimal",
          response_length: "balanced"
        }

        changeset = Style.changeset(%Style{}, attrs)
        assert changeset.valid?, "Formality level #{level} should be valid"
      end)
    end

    test "accepts all valid emoji usage levels" do
      Enum.each(["none", "minimal", "moderate", "frequent"], fn usage ->
        attrs = %{
          formality_level: "neutral",
          emoji_usage: usage,
          response_length: "balanced"
        }

        changeset = Style.changeset(%Style{}, attrs)
        assert changeset.valid?, "Emoji usage #{usage} should be valid"
      end)
    end

    test "accepts all valid response lengths" do
      Enum.each(["concise", "balanced", "detailed", "verbose"], fn length ->
        attrs = %{
          formality_level: "neutral",
          emoji_usage: "minimal",
          response_length: length
        }

        changeset = Style.changeset(%Style{}, attrs)
        assert changeset.valid?, "Response length #{length} should be valid"
      end)
    end
  end

  describe "template/1" do
    test "creates a style template with default values" do
      style = Style.template()
      assert is_nil(style.language_style)
      assert style.formality_level == "neutral"
      assert style.emoji_usage == "minimal"
      assert style.response_length == "balanced"
      assert is_nil(style.interaction_style)
      assert is_nil(style.vocabulary_level)
      assert style.personality_traits == []
      assert style.custom_rules == []
    end

    test "merges provided attributes with defaults" do
      attrs = %{
        language_style: "formal",
        formality_level: "professional",
        personality_traits: ["serious"],
        custom_rules: ["no slang"]
      }

      style = Style.template(attrs)
      assert style.language_style == "formal"
      assert style.formality_level == "professional"
      assert style.emoji_usage == "minimal"
      assert style.response_length == "balanced"
      assert style.personality_traits == ["serious"]
      assert style.custom_rules == ["no slang"]
    end
  end

  # Helper function to convert changeset errors to a map
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
