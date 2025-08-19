defmodule Jido.Character.Identity.Profile do
  @moduledoc """
  Public-facing information that may be updated over time.
  """
  use TypedEctoSchema
  import Ecto.Changeset

  @derive Inspect
  @derive Jason.Encoder
  @primary_key false
  typed_embedded_schema do
    field(:status_message, :string)
    field(:occupation, :string)
    field(:location, :string)
    field(:bio, :string)
    field(:achievements, {:array, :map})
    field(:social_links, {:array, :map})
    field(:public_stats, :map)
    field(:last_active_at, :utc_datetime_usec)
    field(:visibility_settings, :map)
  end

  def changeset(profile \\ %__MODULE__{}, attrs) do
    profile
    |> cast(attrs, [
      :status_message,
      :occupation,
      :location,
      :bio,
      :achievements,
      :social_links,
      :public_stats,
      :last_active_at,
      :visibility_settings
    ])
    |> validate_length(:status_message, max: 280)
    |> validate_length(:bio, max: 1000)
    |> validate_length(:achievements, max: 100)
    |> validate_length(:social_links, max: 20)
    |> validate_achievement_format()
    |> validate_social_link_format()
    |> validate_visibility_settings()
  end

  defp validate_achievement_format(changeset) do
    validate_change(changeset, :achievements, fn _, achievements ->
      Enum.reduce_while(achievements, [], fn achievement, acc ->
        case validate_achievement(achievement) do
          :ok -> {:cont, acc}
          {:error, reason} -> {:halt, [{:achievements, reason}]}
        end
      end)
    end)
  end

  defp validate_achievement(achievement) do
    required_keys = ["title", "description", "earned_at"]

    cond do
      !is_map(achievement) ->
        {:error, "achievement must be a map"}

      !Enum.all?(required_keys, &Map.has_key?(achievement, &1)) ->
        {:error, "achievement must contain title, description, and earned_at"}

      true ->
        :ok
    end
  end

  defp validate_social_link_format(changeset) do
    validate_change(changeset, :social_links, fn _, links ->
      Enum.reduce_while(links, [], fn link, acc ->
        case validate_social_link(link) do
          :ok -> {:cont, acc}
          {:error, reason} -> {:halt, [{:social_links, reason}]}
        end
      end)
    end)
  end

  defp validate_social_link(link) do
    required_keys = ["platform", "url"]

    cond do
      !is_map(link) ->
        {:error, "social link must be a map"}

      !Enum.all?(required_keys, &Map.has_key?(link, &1)) ->
        {:error, "social link must contain platform and url"}

      !String.starts_with?(link["url"], "https://") ->
        {:error, "social link url must start with https://"}

      true ->
        :ok
    end
  end

  defp validate_visibility_settings(changeset) do
    validate_change(changeset, :visibility_settings, fn _, settings ->
      required_fields = [:profile_visible, :achievements_visible, :social_links_visible]

      if is_map(settings) && Enum.all?(required_fields, &Map.has_key?(settings, &1)) do
        []
      else
        [{:visibility_settings, "must contain all required visibility flags"}]
      end
    end)
  end

  @spec template(map()) :: %__MODULE__{}
  def template(attrs \\ %{}) do
    %__MODULE__{
      status_message: nil,
      occupation: nil,
      location: nil,
      bio: nil,
      achievements: [],
      social_links: [],
      public_stats: %{},
      last_active_at: DateTime.utc_now(),
      visibility_settings: %{
        profile_visible: true,
        achievements_visible: true,
        social_links_visible: true
      }
    }
    |> Map.merge(attrs)
  end
end
