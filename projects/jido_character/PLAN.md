Core Implementation

Feature: Jido.CharacterExpansions {
What:
- “Extend the current JIDO character module to incorporate new submodules (Cognitive, Evolution, World, Economics, IdentitySystem) as described in DATA_PLAN.md”
- “Maintain immutability semantics by returning new character structs upon every modification”
- “Add test-driven development plan to ensure each submodule is correctly implemented and integrated”
- “Enhance persistence layer to handle new submodules across various stores (ETS, Ecto, JSONB)”
- “Allow for incremental evolution of character data while preserving older states”

Boundaries:
- “Character data is immutable: all updates return a new character struct”
- “New submodules must be embedded or referenced in the top-level Jido.Character schema”
- “Must maintain existing SoulScript compliance and seamlessly import/export SoulScript data”
- “All expansions must pass newly added ExUnit tests before merging”
- “Adapters must provide consistent storage and retrieval of expanded character data”
- “Evolution logic must not compromise prior snapshots or data integrity”

Success:
- “Cognitive, Evolution, World, Economics, and IdentitySystem submodules exist with typed embedded schemas”
- “Clear TDD approach with separate test files for each new submodule”
- “Jido.Character updates do not mutate existing data in place”
- “Persistence adapters can store and retrieve extended character data”
- “Characters can evolve over time; tests confirm version increments or time-based changes”
- “All test suites and submodule tests pass consistently”
}

Implementation Plan

Below is a step-by-step plan that builds upon your existing JIDO character codebase, guided by a TDD approach. It outlines how to add the new submodules, manage immutability, integrate with the existing SoulScript structure, and expand the persistence adapters.

1. Add Cognitive Submodule

Goal
Add a new Cognitive embedded schema to represent memory, knowledge, and emotional states as described in DATA_PLAN.md. This includes sub-structures for Memory, Knowledge, and Emotional.

Proposed Files/Modules
	1.	lib/jido_character/cognitive.ex
	2.	lib/jido_character/cognitive/memory.ex
	3.	lib/jido_character/cognitive/knowledge.ex
	4.	lib/jido_character/cognitive/emotional.ex
	5.	test/jido_character/cognitive_test.exs and/or sub-tests for each sub-structure

Data Structures & Fields
	•	Jido.Character.Cognitive

defmodule Jido.Character.Cognitive do
  use TypedEctoSchema
  import Ecto.Changeset

  typed_embedded_schema do
    embeds_many :memories, Jido.Character.Cognitive.Memory
    embeds_many :knowledge, Jido.Character.Cognitive.Knowledge
    embeds_one :emotional, Jido.Character.Cognitive.Emotional
  end

  def changeset(cognitive, attrs) do
    cognitive
    |> cast(attrs, [])
    |> cast_embed(:memories)
    |> cast_embed(:knowledge)
    |> cast_embed(:emotional)
  end
end


	•	Memory

defmodule Jido.Character.Cognitive.Memory do
  use TypedEctoSchema
  import Ecto.Changeset

  typed_embedded_schema do
    field :description, :string
    field :timestamp, :utc_datetime_usec
    # Possibly more metadata: importance, tags, associations, etc.
  end

  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [:description, :timestamp])
    |> validate_required([:description])
  end
end


	•	Knowledge

defmodule Jido.Character.Cognitive.Knowledge do
  use TypedEctoSchema
  import Ecto.Changeset

  typed_embedded_schema do
    field :fact, :string
    field :source, :string
    field :confidence, :float, default: 0.75
    # Possibly more fields for classification
  end

  def changeset(knowledge, attrs) do
    knowledge
    |> cast(attrs, [:fact, :source, :confidence])
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
  end
end


	•	Emotional

defmodule Jido.Character.Cognitive.Emotional do
  use TypedEctoSchema
  import Ecto.Changeset

  typed_embedded_schema do
    field :mood, :string
    field :intensity, :float, default: 0.5
    # Possibly store multiple emotion tags or a map
  end

  def changeset(emotional, attrs) do
    emotional
    |> cast(attrs, [:mood, :intensity])
    |> validate_number(:intensity, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
  end
end



Integration into Jido.Character
	•	In lib/jido_character.ex:

typed_embedded_schema do
  # existing fields

  embeds_one :cognitive, Jido.Character.Cognitive, on_replace: :update
  # ...
end

def changeset(character \\ %__MODULE__{}, attrs) do
  character
  |> cast(attrs, [:id, :created_at, :updated_at])
  # ...
  |> cast_embed(:cognitive)
end



Test-Driven Development Steps
	1.	Step 1: Write Failing Tests
	•	In test/jido_character/cognitive_test.exs, create tests for memory CRUD, knowledge additions, emotional changes, ensuring immutability.
	2.	Step 2: Implement Minimal Code
	•	Create Cognitive schema modules above, with basic changeset validations.
	3.	Step 3: Refine
	•	Update test coverage for corner cases (e.g., large memory arrays, emotional intensity out of range).

2. Add Evolution Submodule

Goal
Introduce an Evolution schema for tracking TemporalState, GrowthSystem, and a History log. This supports versioned changes, historical logs of transformations, etc.

Proposed Files/Modules
	1.	lib/jido_character/evolution.ex
	2.	lib/jido_character/evolution/temporal_state.ex
	3.	lib/jido_character/evolution/growth_system.ex
	4.	lib/jido_character/evolution/history.ex
	5.	test/jido_character/evolution_test.exs

Data Structures
	•	Evolution

defmodule Jido.Character.Evolution do
  use TypedEctoSchema
  import Ecto.Changeset

  typed_embedded_schema do
    embeds_one :temporal_state, Jido.Character.Evolution.TemporalState
    embeds_one :growth_system, Jido.Character.Evolution.GrowthSystem
    embeds_many :history, Jido.Character.Evolution.History
  end

  def changeset(evolution, attrs) do
    evolution
    |> cast(attrs, [])
    |> cast_embed(:temporal_state)
    |> cast_embed(:growth_system)
    |> cast_embed(:history)
  end
end


	•	TemporalState

defmodule Jido.Character.Evolution.TemporalState do
  use TypedEctoSchema
  import Ecto.Changeset

  typed_embedded_schema do
    field :age, :integer, default: 0
    field :maturity, :float, default: 0.0
    # Possibly more fields like "current_stage"
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [:age, :maturity])
    |> validate_number(:maturity, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
  end
end


	•	GrowthSystem

defmodule Jido.Character.Evolution.GrowthSystem do
  use TypedEctoSchema
  import Ecto.Changeset

  typed_embedded_schema do
    field :rules, :map, default: %{}
    # E.g., thresholds for incrementing traits or knowledge
  end

  def changeset(gs, attrs) do
    gs
    |> cast(attrs, [:rules])
  end
end


	•	History

defmodule Jido.Character.Evolution.History do
  use TypedEctoSchema
  import Ecto.Changeset

  typed_embedded_schema do
    field :event, :string
    field :timestamp, :utc_datetime_usec
    field :details, :map, default: %{}
  end

  def changeset(history, attrs) do
    history
    |> cast(attrs, [:event, :timestamp, :details])
    |> validate_required([:event, :timestamp])
  end
end



Integration into Jido.Character

typed_embedded_schema do
  # existing fields
  embeds_one :evolution, Jido.Character.Evolution, on_replace: :update
end

def changeset(character, attrs) do
  character
  |> cast(attrs, [:id, :created_at, :updated_at])
  # ...
  |> cast_embed(:evolution)
end

Test-Driven Development Steps
	1.	Step 1: Create tests in test/jido_character/evolution_test.exs for:
	•	Increasing age and verifying it returns a new character
	•	Logging events in history with timestamps
	•	Validating growth rules
	2.	Step 2: Implement minimal code to pass
	3.	Step 3: Validate advanced scenarios (e.g., large histories, invalid maturities)

3. Add World Submodule

Goal
Add a World module capturing Context, Social, and Cultural aspects. This influences the character’s environment and potential relationships.

Proposed Files/Modules
	1.	lib/jido_character/world.ex
	2.	lib/jido_character/world/context.ex
	3.	lib/jido_character/world/social.ex
	4.	lib/jido_character/world/cultural.ex
	5.	test/jido_character/world_test.exs

Data Structures

defmodule Jido.Character.World do
  use TypedEctoSchema
  import Ecto.Changeset

  typed_embedded_schema do
    embeds_one :context, Jido.Character.World.Context
    embeds_many :social, Jido.Character.World.Social
    embeds_one :cultural, Jido.Character.World.Cultural
  end

  def changeset(world, attrs) do
    world
    |> cast(attrs, [])
    |> cast_embed(:context)
    |> cast_embed(:social)
    |> cast_embed(:cultural)
  end
end

	•	Context

defmodule Jido.Character.World.Context do
  use TypedEctoSchema
  import Ecto.Changeset

  typed_embedded_schema do
    field :location, :string
    field :time_of_day, :string
    # Possibly more ephemeral context
  end

  def changeset(ctx, attrs) do
    ctx
    |> cast(attrs, [:location, :time_of_day])
  end
end


	•	Social

defmodule Jido.Character.World.Social do
  use TypedEctoSchema
  import Ecto.Changeset

  typed_embedded_schema do
    field :relationship_id, :string  # e.g., link to a Relationship object or ID
    field :status, :string
    # Possibly additional social details
  end

  def changeset(social, attrs) do
    social
    |> cast(attrs, [:relationship_id, :status])
    |> validate_required([:relationship_id])
  end
end


	•	Cultural

defmodule Jido.Character.World.Cultural do
  use TypedEctoSchema
  import Ecto.Changeset

  typed_embedded_schema do
    field :norms, {:array, :string}, default: []
    field :language, :string
  end

  def changeset(cultural, attrs) do
    cultural
    |> cast(attrs, [:norms, :language])
  end
end



Integration into Jido.Character

typed_embedded_schema do
  # ...
  embeds_one :world, Jido.Character.World, on_replace: :update
end

def changeset(character, attrs) do
  character
  # ...
  |> cast_embed(:world)
end

TDD Steps
	1.	Write tests in world_test.exs for each embedded schema
	2.	Minimal code in each module
	3.	Validate advanced logic (e.g., changing location influences expression, if relevant)

4. Add Economics Submodule

Goal
Track finances: Wallets, Assets, Income, Transactions, and derived EconomicStatus.

Proposed Files/Modules
	1.	lib/jido_character/economics.ex
	2.	lib/jido_character/economics/wallet.ex
	3.	lib/jido_character/economics/assets.ex
	4.	lib/jido_character/economics/income.ex
	5.	lib/jido_character/economics/transactions.ex
	6.	lib/jido_character/economics/economic_status.ex
	7.	test/jido_character/economics_test.exs

Data Structures

defmodule Jido.Character.Economics do
  use TypedEctoSchema
  import Ecto.Changeset

  typed_embedded_schema do
    embeds_many :wallets, Jido.Character.Economics.Wallet
    embeds_many :assets, Jido.Character.Economics.Assets
    embeds_many :income, Jido.Character.Economics.Income
    embeds_many :transactions, Jido.Character.Economics.Transactions
    embeds_one :economic_status, Jido.Character.Economics.EconomicStatus
  end

  def changeset(econ, attrs) do
    econ
    |> cast(attrs, [])
    |> cast_embed(:wallets)
    |> cast_embed(:assets)
    |> cast_embed(:income)
    |> cast_embed(:transactions)
    |> cast_embed(:economic_status)
  end
end

Integration & TDD
	•	As before, embed :economics in Jido.Character.
	•	Write tests covering additions to wallets, posting transactions, updating derived economic_status.

5. Add IdentitySystem Submodule

Goal
Manage multiple personas or external platform identities. Keep synergy with the existing Identity but store more advanced multi-identity logic.

Proposed Files/Modules
	1.	lib/jido_character/identity_system.ex
	2.	lib/jido_character/identity_system/personas.ex
	3.	lib/jido_character/identity_system/platform_identities.ex
	4.	lib/jido_character/identity_system/identity_relationships.ex
	5.	lib/jido_character/identity_system/identity_management.ex
	6.	test/jido_character/identity_system_test.exs

6. Update Persistence Layer

Now that we have more submodules, ensure each adapter correctly stores and retrieves the expanded data.

Memory Adapter (in-memory)
Already implemented. Verify it can handle the new embedded fields (it should, as :erlang.term_to_binary/1 can handle any updated struct).

ETS Adapter
	•	Confirm that storing the updated Jido.Character with embedded submodules works.
	•	Potentially no code change needed if you’re storing the entire struct in ETS, but confirm the :ets.insert usage can handle changes in data shape.

Ecto Adapter
	•	If you want to store the entire Jido.Character in a JSONB column, add migrations to add a character_data (JSONB) field in your table.
	•	Then you can define a DB-backed schema referencing that column, e.g.:

schema "characters" do
  field :character_data, :map
  timestamps()
end


	•	On save, run Jason.encode!(character_struct) or use a custom Ecto.Type that handles the embedded schema.

Potential Implementation

defmodule Jido.Character.Persistence.Postgres do
  @behaviour Jido.Character.Persistence.Adapter

  alias Jido.Character
  alias MyApp.Repo
  alias MyApp.CharacterRecord

  def save(%Jido.Character{} = char) do
    record_attrs = %{character_data: Jason.encode!(char)}
    changeset = Ecto.Changeset.change(%CharacterRecord{}, record_attrs)

    case Repo.insert_or_update(changeset) do
      {:ok, record} -> {:ok, char}
      {:error, _}   -> {:error, :storage_error}
    end
  end

  def get(id) do
    case Repo.get(CharacterRecord, id) do
      nil -> {:error, :not_found}
      record ->
        with {:ok, data} <- Jason.decode(record.character_data),
             {:ok, char} <- Jido.Character.from_json(Jason.encode!(data)) do
          {:ok, char}
        else
          _ -> {:error, :invalid_data}
        end
    end
  end

  def delete(id) do
    # ...
  end
end

7. Ensure Immutability & Evolution
	1.	Every “update” function (e.g. Cognitive.add_memory(character, memory_attrs)) should:
	•	Retrieve the existing character.cognitive
	•	Build a changeset with the new memory
	•	Apply changes, produce a new %Jido.Character{...}
	•	Return the new version
Example pattern:

def add_memory(%Jido.Character{} = char, memory_attrs) do
  new_memories = [memory_attrs | char.cognitive.memories]

  new_cognitive =
    char.cognitive
    |> Jido.Character.Cognitive.changeset(%{memories: new_memories})
    |> Ecto.Changeset.apply_changes()

  Jido.Character.update(char, %{cognitive: new_cognitive})
end


	2.	Versioning or “Evolution increment”
	•	If you want an auto-incrementing version, you can store it in Jido.Character.Evolution.TemporalState or in the top-level character.version.
	•	Each time you do Jido.Character.update/2, increment or adjust the version. This ensures prior states remain distinct.
	3.	Testing
	•	Test that repeated calls produce new structures with updated timestamps or version fields.
	•	Confirm old references remain intact.

8. Detailed Test-Driven Development Approach
	1.	Create/Extend Test Files
	•	test/jido_character/cognitive_test.exs
	•	test/jido_character/evolution_test.exs
	•	test/jido_character/world_test.exs
	•	test/jido_character/economics_test.exs
	•	test/jido_character/identity_system_test.exs
	2.	Write Failing Tests First
	•	Each submodule’s test file defines the public API you plan to expose (e.g., add_memory/2, log_event/2, update_context/2).
	•	Confirm immutability by comparing old struct references to new ones.
	3.	Implement Minimal Code
	•	Add submodules, fields, changeset logic, plus an updating function in Jido.Character.Core or relevant module.
	•	Return new character struct from each function.
	4.	Iterate
	•	Expand tests for boundary conditions, errors, larger sets (e.g., 1000 memories).
	•	Adjust schema validations (e.g., max arrays, required fields).
	5.	Adapter Tests
	•	Update or create test/persistence/ets_test.exs, test/persistence/memory_test.exs, and test/persistence/postgres_test.exs to verify storing a fully populated character with new submodules.

9. Summary of Architectural Decisions
	1.	Encapsulation
	•	Each domain area (Cognitive, Evolution, World, Economics, IdentitySystem) is its own embedded schema under Jido.Character.
	•	Substructures are further embedded (e.g., Cognitive.Memory).
	2.	Immutability
	•	All modifications go through the main Jido.Character.update/2 pipeline, returning a new struct.
	3.	Persistence
	•	Memory, ETS, and JSONB-based Ecto solutions each store/retrieve the entire Jido.Character struct.
	•	Minimal changes needed beyond verifying larger data shape.
	4.	Evolution
	•	The Evolution module provides versioning or historical logs. This can be optional or required depending on your domain needs.
	5.	Integration with SoulScript
	•	Keep existing soulscript field in Jido.Character. The new expansions do not conflict with or override SoulScript structure but can be serialized alongside it.

Conclusion

This plan extends your JIDO character system with additional submodules for Cognitive, Evolution, World, Economics, and IdentitySystem using a clearly defined, test-driven development workflow. Each submodule follows the same pattern:
	•	Define an embedded schema
	•	Integrate it into Jido.Character
	•	Write unit tests and TDD steps
	•	Confirm immutability and multi-adapter persistence

By following this structured approach, your codebase grows incrementally while preserving the foundation of SoulScript compliance and your existing identity/personality architecture.