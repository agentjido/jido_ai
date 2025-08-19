defmodule Jido.Character do
  use TypedEctoSchema
  import Ecto.Changeset

  @derive {Jason.Encoder, except: []}
  @primary_key false
  typed_embedded_schema do
    # Existing JIDO fields
    field(:id, :string)
    embeds_one(:identity, Jido.Character.Identity, on_replace: :update)
    embeds_one(:personality, Jido.Character.Personality, on_replace: :update)

    # SoulScript block
    embeds_one(:soulscript, Jido.Character.SoulScript.Root, on_replace: :update)

    # Cognitive module
    embeds_one(:cognitive, Jido.Character.Cognitive, on_replace: :update)

    # Evolution module
    embeds_one(:evolution, Jido.Character.Evolution, on_replace: :update)

    # These will be implemented in future iterations
    # embeds_one :personality_extras, Jido.Character.PersonalityExtras
    # embeds_one :world, Jido.Character.World
    # embeds_one :economics, Jido.Character.Economics
    # embeds_one :identity_system, Jido.Character.IdentitySystem

    field(:created_at, :utc_datetime_usec)
    field(:updated_at, :utc_datetime_usec)
  end

  def changeset(character \\ %__MODULE__{}, attrs) do
    character
    |> cast(attrs, [:id, :created_at, :updated_at])
    |> cast_embed(:identity)
    |> cast_embed(:personality)
    |> cast_embed(:soulscript)
    |> cast_embed(:cognitive)
    |> cast_embed(:evolution)
    |> validate_required([:id, :soulscript])
  end

  # Public API delegates to Core
  defdelegate new(id \\ nil), to: Jido.Character.Core
  defdelegate get(id), to: Jido.Character.Core
  defdelegate update(character, attrs), to: Jido.Character.Core
  defdelegate delete(id), to: Jido.Character.Core
  defdelegate clone(character, new_id), to: Jido.Character.Core
  defdelegate validate(character), to: Jido.Character.Core
  defdelegate to_json(character), to: Jido.Character.Core
  defdelegate from_json(json), to: Jido.Character.Core

  # Template for creating new characters
  def template(attrs \\ %{}) do
    now = DateTime.utc_now()

    base = %__MODULE__{
      id: nil,
      created_at: now,
      updated_at: now,
      identity: Jido.Character.Identity.template(),
      personality: Jido.Character.Personality.template(),
      cognitive: %Jido.Character.Cognitive{
        memories: [],
        knowledge: [],
        emotional: %Jido.Character.Cognitive.Emotional{
          mood: "neutral",
          intensity: 0.5
        }
      },
      evolution: %Jido.Character.Evolution{
        temporal_state: %Jido.Character.Evolution.TemporalState{
          age: 0,
          maturity: 0.0,
          stage: "initial",
          last_evolved_at: now
        },
        growth_system: %Jido.Character.Evolution.GrowthSystem{},
        history: []
      },
      soulscript: %Jido.Character.SoulScript.Root{
        version: "1.0",
        id: UUID.uuid4(),
        entity: %Jido.Character.SoulScript.Entity{
          form: "human"
        },
        personality: %Jido.Character.SoulScript.Personality{
          name: "New Character"
        }
      }
    }

    struct(base, attrs)
  end
end
