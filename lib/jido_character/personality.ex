defmodule Jido.Character.Personality do
  @moduledoc """
  Encapsulates the character's internal tendencies, nature, and how that internal nature is communicated.
  Manages traits, narrative, behavior, and expression components.
  """
  use TypedEctoSchema
  import Ecto.Changeset

  alias Jido.Character.Personality.{Traits, Narrative, Behavior, Expression}

  @type character :: Jido.Character.t()
  @type error :: Jido.Character.error()

  @derive {Jason.Encoder, except: []}
  @primary_key false
  typed_embedded_schema do
    embeds_one(:traits, Traits, on_replace: :update)
    embeds_one(:narrative, Narrative, on_replace: :update)
    embeds_one(:behavior, Behavior, on_replace: :update)
    embeds_one(:expression, Expression, on_replace: :update)
  end

  def changeset(personality \\ %__MODULE__{}, attrs) do
    personality
    |> cast(attrs, [])
    |> cast_embed(:traits)
    |> cast_embed(:narrative)
    |> cast_embed(:behavior)
    |> cast_embed(:expression)
    |> validate_required([:traits])
  end

  def template(attrs \\ %{}) do
    %__MODULE__{
      traits: Traits.template(),
      narrative: Narrative.template(),
      behavior: Behavior.template(),
      expression: Expression.template()
    }
    |> Map.merge(attrs)
  end

  @doc "Updates multiple personality fields at once"
  @spec update_personality(character() | {:ok, character()}, map()) ::
          {:ok, character()} | error()
  def update_personality({:ok, character}, attrs), do: update_personality(character, attrs)

  def update_personality(%Jido.Character{} = character, attrs) when is_map(attrs) do
    Jido.Character.update(character, %{personality: attrs})
  end

  @doc "Gets the traits"
  @spec get_traits(character()) :: Traits.t() | nil
  def get_traits(%Jido.Character{personality: %{traits: traits}}), do: traits

  @doc "Gets the narrative"
  @spec get_narrative(character()) :: Narrative.t() | nil
  def get_narrative(%Jido.Character{personality: %{narrative: narrative}}), do: narrative

  @doc "Gets the behavior"
  @spec get_behavior(character()) :: Behavior.t() | nil
  def get_behavior(%Jido.Character{personality: %{behavior: behavior}}), do: behavior

  @doc "Gets the expression"
  @spec get_expression(character()) :: Expression.t() | nil
  def get_expression(%Jido.Character{personality: %{expression: expression}}), do: expression

  @doc "Updates the traits"
  @spec update_traits(character(), map()) :: {:ok, character()} | error()
  def update_traits(%Jido.Character{} = character, traits_attrs) do
    update_personality(character, %{traits: traits_attrs})
  end

  @doc "Updates the narrative"
  @spec update_narrative(character(), map()) :: {:ok, character()} | error()
  def update_narrative(%Jido.Character{} = character, narrative_attrs) do
    update_personality(character, %{narrative: narrative_attrs})
  end

  @doc "Updates the behavior"
  @spec update_behavior(character(), map()) :: {:ok, character()} | error()
  def update_behavior(%Jido.Character{} = character, behavior_attrs) do
    update_personality(character, %{behavior: behavior_attrs})
  end

  @doc "Updates the expression"
  @spec update_expression(character(), map()) :: {:ok, character()} | error()
  def update_expression(%Jido.Character{} = character, expression_attrs) do
    update_personality(character, %{expression: expression_attrs})
  end
end
