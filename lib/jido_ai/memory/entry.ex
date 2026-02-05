defmodule Jido.AI.Memory.Entry do
  @moduledoc """
  A single memory record scoped to an agent.

  Entries are the fundamental unit of agent memory, storing a value
  associated with a key, optional tags for categorization, and
  arbitrary metadata.

  ## Fields

  - `:agent_id` - The agent this memory belongs to
  - `:key` - Unique key within the agent's memory space
  - `:value` - The stored value (any term)
  - `:tags` - List of string tags for categorization and recall
  - `:metadata` - Arbitrary metadata map
  - `:inserted_at` - When the entry was first created
  - `:updated_at` - When the entry was last modified
  """

  @type t :: %__MODULE__{
          agent_id: String.t(),
          key: String.t(),
          value: term(),
          tags: [String.t()],
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :agent_id,
    :key,
    :value,
    :inserted_at,
    :updated_at,
    tags: [],
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    %__MODULE__{
      agent_id: Map.fetch!(attrs, :agent_id),
      key: Map.fetch!(attrs, :key),
      value: Map.get(attrs, :value),
      tags: Map.get(attrs, :tags, []),
      metadata: Map.get(attrs, :metadata, %{}),
      inserted_at: Map.get(attrs, :inserted_at, now),
      updated_at: Map.get(attrs, :updated_at, now)
    }
  end
end
