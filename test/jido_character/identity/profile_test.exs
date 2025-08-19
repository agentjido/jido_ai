defmodule Jido.Character.Identity.ProfileTest do
  use ExUnit.Case, async: true
  alias Jido.Character.Identity.Profile

  describe "changeset/2" do
    test "validates status message length" do
      attrs = %{status_message: String.duplicate("a", 281)}
      changeset = Profile.changeset(%Profile{}, attrs)
      refute changeset.valid?
      assert "should be at most 280 character(s)" in errors_on(changeset).status_message
    end

    test "validates bio length" do
      attrs = %{bio: String.duplicate("a", 1001)}
      changeset = Profile.changeset(%Profile{}, attrs)
      refute changeset.valid?
      assert "should be at most 1000 character(s)" in errors_on(changeset).bio
    end

    test "validates achievements length" do
      attrs = %{achievements: List.duplicate(%{}, 101)}
      changeset = Profile.changeset(%Profile{}, attrs)
      refute changeset.valid?
      assert "should have at most 100 item(s)" in errors_on(changeset).achievements
    end

    test "validates social links length" do
      attrs = %{social_links: List.duplicate(%{}, 21)}
      changeset = Profile.changeset(%Profile{}, attrs)
      refute changeset.valid?
      assert "should have at most 20 item(s)" in errors_on(changeset).social_links
    end

    test "validates achievement format" do
      attrs = %{
        achievements: [
          %{"invalid" => "achievement"}
        ]
      }

      changeset = Profile.changeset(%Profile{}, attrs)
      refute changeset.valid?

      assert "achievement must contain title, description, and earned_at" in errors_on(changeset).achievements
    end

    test "validates social link format" do
      attrs = %{
        social_links: [
          %{"platform" => "twitter", "url" => "http://invalid-url"}
        ]
      }

      changeset = Profile.changeset(%Profile{}, attrs)
      refute changeset.valid?
      assert "social link url must start with https://" in errors_on(changeset).social_links
    end

    test "validates visibility settings" do
      attrs = %{
        visibility_settings: %{
          "invalid_setting" => true
        }
      }

      changeset = Profile.changeset(%Profile{}, attrs)
      refute changeset.valid?

      assert "must contain all required visibility flags" in errors_on(changeset).visibility_settings
    end

    test "creates valid changeset with valid attributes" do
      attrs = %{
        status_message: "Available",
        occupation: "Developer",
        location: "San Francisco",
        bio: "A test bio",
        achievements: [
          %{
            "title" => "First Achievement",
            "description" => "Test achievement",
            "earned_at" => "2023-01-01T00:00:00Z"
          }
        ],
        social_links: [
          %{
            "platform" => "twitter",
            "url" => "https://twitter.com/test"
          }
        ],
        public_stats: %{"followers" => 100},
        last_active_at: DateTime.utc_now(),
        visibility_settings: %{
          profile_visible: true,
          achievements_visible: true,
          social_links_visible: true
        }
      }

      changeset = Profile.changeset(%Profile{}, attrs)
      assert changeset.valid?
    end
  end

  describe "template/1" do
    test "creates a profile template with default values" do
      profile = Profile.template()
      assert is_nil(profile.status_message)
      assert is_nil(profile.occupation)
      assert is_nil(profile.location)
      assert is_nil(profile.bio)
      assert profile.achievements == []
      assert profile.social_links == []
      assert profile.public_stats == %{}
      assert %DateTime{} = profile.last_active_at

      assert profile.visibility_settings == %{
               profile_visible: true,
               achievements_visible: true,
               social_links_visible: true
             }
    end

    test "merges provided attributes with defaults" do
      attrs = %{
        status_message: "Custom status",
        occupation: "Custom occupation",
        visibility_settings: %{
          profile_visible: false,
          achievements_visible: true,
          social_links_visible: true
        }
      }

      profile = Profile.template(attrs)
      assert profile.status_message == "Custom status"
      assert profile.occupation == "Custom occupation"
      assert profile.visibility_settings.profile_visible == false
      assert profile.achievements == []
      assert profile.social_links == []
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
