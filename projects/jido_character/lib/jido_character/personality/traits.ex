defmodule Jido.Character.Personality.Traits do
  @moduledoc """
  Core personality attributes or temperament indicators that form the baseline
  template for behavior and expression.
  """
  use TypedEctoSchema
  import Ecto.Changeset

  @type trait_value :: 0..100

  @derive {Jason.Encoder, except: []}
  @primary_key false
  typed_embedded_schema do
    # Core personality dimensions (Big Five)
    field(:openness, :integer, default: 50)
    field(:conscientiousness, :integer, default: 50)
    field(:extraversion, :integer, default: 50)
    field(:agreeableness, :integer, default: 50)
    field(:neuroticism, :integer, default: 50)

    # Custom traits stored as map
    field(:custom_traits, :map, default: %{})
  end

  def changeset(traits \\ %__MODULE__{}, attrs) do
    traits
    |> cast(attrs, [
      :openness,
      :conscientiousness,
      :extraversion,
      :agreeableness,
      :neuroticism,
      :custom_traits
    ])
    |> validate_trait_range(:openness)
    |> validate_trait_range(:conscientiousness)
    |> validate_trait_range(:extraversion)
    |> validate_trait_range(:agreeableness)
    |> validate_trait_range(:neuroticism)
  end

  defp validate_trait_range(changeset, field) do
    validate_inclusion(changeset, field, 0..100)
  end

  @spec template(map()) :: %__MODULE__{}
  def template(attrs \\ %{}) do
    %__MODULE__{
      openness: 50,
      conscientiousness: 50,
      extraversion: 50,
      agreeableness: 50,
      neuroticism: 50,
      custom_traits: %{}
    }
    |> Map.merge(attrs)
  end

  @doc """
  Adds a custom trait to the traits map.
  Returns {:ok, updated_traits} or {:error, changeset}
  """
  @spec add_custom_trait(t(), String.t(), trait_value()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def add_custom_trait(traits, name, value) when value in 0..100 do
    updated_custom_traits = Map.put(traits.custom_traits, name, value)

    traits
    |> changeset(%{custom_traits: updated_custom_traits})
    |> apply_action(:update)
  end

  @doc """
  Removes a custom trait from the traits map.
  """
  @spec remove_custom_trait(t(), String.t()) :: {:ok, t()}
  def remove_custom_trait(traits, name) do
    {:ok, %{traits | custom_traits: Map.delete(traits.custom_traits, name)}}
  end

  @doc """
  Updates a trait value if it's valid.
  Returns {:ok, updated_traits} or {:error, changeset}
  """
  @spec update_trait(t(), atom(), trait_value()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update_trait(traits, trait, value)
      when trait in [:openness, :conscientiousness, :extraversion, :agreeableness, :neuroticism] do
    traits
    |> changeset(%{trait => value})
    |> apply_action(:update)
  end
end
