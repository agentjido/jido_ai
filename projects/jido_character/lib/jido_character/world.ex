defmodule Jido.Character.World do
  use TypedEctoSchema
  import Ecto.Changeset

  alias Jido.Character.World.{Context, Social, Cultural}

  typed_embedded_schema do
    embeds_one(:context, Context, on_replace: :update)
    embeds_many(:social, Social, on_replace: :delete)
    embeds_one(:cultural, Cultural, on_replace: :update)
  end

  def changeset(world, attrs) when is_map(attrs) do
    world
    |> cast(attrs, [])
    |> cast_embed(:context)
    |> cast_embed(:social)
    |> cast_embed(:cultural)
  end

  def update_context(world, location, environment, current_topic) do
    attrs = %{
      context: %{
        location: location,
        environment: environment,
        current_topic: current_topic,
        last_updated_at: DateTime.utc_now()
      }
    }

    changeset(world, attrs)
  end

  def find_relationships_by_type(world, relationship_type) do
    Enum.filter(world.social, &(&1.relationship_type == relationship_type))
  end

  def find_relationship(world, target_id) do
    Enum.find(world.social, &(&1.target_id == target_id))
  end

  def record_interaction(world, target_id, opts \\ []) do
    case find_relationship(world, target_id) do
      nil ->
        {:error, :relationship_not_found}

      _relationship ->
        trust_change = Keyword.get(opts, :trust_change, 0.0)
        familiarity_increase = Keyword.get(opts, :familiarity_increase, 0.0)

        updated_social =
          Enum.map(world.social, fn rel ->
            if rel.target_id == target_id do
              %{
                relationship_type: rel.relationship_type,
                target_id: rel.target_id,
                trust_level: min(1.0, max(0.0, rel.trust_level + trust_change)),
                familiarity: min(1.0, rel.familiarity + familiarity_increase),
                last_interaction_at: DateTime.utc_now(),
                metadata: rel.metadata
              }
            else
              Map.from_struct(rel)
            end
          end)

        changeset(world, %{social: updated_social})
    end
  end

  def get_cultural_norm(world, key) do
    get_in(world, [Access.key(:cultural), Access.key(:norms), key])
  end

  def get_cultural_custom(world, key) do
    get_in(world, [Access.key(:cultural), Access.key(:customs), key])
  end

  def find_cultural_references(world, pattern) do
    Enum.filter(world.cultural.references, &String.contains?(&1, pattern))
  end

  def matches_cultural_background?(world, pattern) do
    String.contains?(world.cultural.background, pattern)
  end

  def current_environment(world) do
    world.context.environment
  end
end
