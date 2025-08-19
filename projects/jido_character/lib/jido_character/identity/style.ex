defmodule Jido.Character.Identity.Style do
  @moduledoc """
  Default expression rules and preferred communication style for the character.
  """
  use TypedEctoSchema
  import Ecto.Changeset

  @derive Inspect
  @derive Jason.Encoder
  @primary_key false
  typed_embedded_schema do
    field(:language_style, :string)
    field(:formality_level, :string)
    field(:emoji_usage, :string)
    field(:response_length, :string)
    field(:interaction_style, :string)
    field(:vocabulary_level, :string)
    field(:personality_traits, {:array, :string})
    field(:custom_rules, {:array, :string})
  end

  @valid_formality_levels ["casual", "neutral", "formal", "professional"]
  @valid_emoji_usage ["none", "minimal", "moderate", "frequent"]
  @valid_response_lengths ["concise", "balanced", "detailed", "verbose"]

  def changeset(style \\ %__MODULE__{}, attrs) do
    style
    |> cast(attrs, [
      :language_style,
      :formality_level,
      :emoji_usage,
      :response_length,
      :interaction_style,
      :vocabulary_level,
      :personality_traits,
      :custom_rules
    ])
    |> validate_required([:formality_level, :emoji_usage, :response_length])
    |> validate_inclusion(:formality_level, @valid_formality_levels)
    |> validate_inclusion(:emoji_usage, @valid_emoji_usage)
    |> validate_inclusion(:response_length, @valid_response_lengths)
    |> validate_length(:personality_traits, max: 10)
    |> validate_length(:custom_rules, max: 20)
  end

  @spec template(map()) :: %__MODULE__{}
  def template(attrs \\ %{}) do
    %__MODULE__{
      language_style: nil,
      formality_level: "neutral",
      emoji_usage: "minimal",
      response_length: "balanced",
      interaction_style: nil,
      vocabulary_level: nil,
      personality_traits: [],
      custom_rules: []
    }
    |> Map.merge(attrs)
  end
end
