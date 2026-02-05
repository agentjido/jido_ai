defmodule Jido.AI.Memory.Signal do
  @moduledoc """
  Signal types for memory operations.

  These signals are emitted when memory is stored, recalled, or forgotten,
  enabling observability and event-driven reactions to memory changes.

  ## Signal Types

  - `Stored` - Emitted when a memory entry is created or updated (`memory.stored`)
  - `Recalled` - Emitted when memory is recalled (`memory.recalled`)
  - `Forgotten` - Emitted when memory entries are deleted (`memory.forgotten`)
  """

  defmodule Stored do
    @moduledoc """
    Signal emitted when a memory entry is stored.

    ## Data Fields

    - `:agent_id` (required) - The agent that owns the memory
    - `:key` (required) - The memory key
    - `:tags` (optional) - Tags associated with the entry
    """

    use Jido.Signal,
      type: "memory.stored",
      default_source: "/memory",
      schema: [
        agent_id: [type: :string, required: true, doc: "Agent that owns the memory"],
        key: [type: :string, required: true, doc: "Memory key"],
        tags: [type: {:list, :string}, default: [], doc: "Tags associated with the entry"]
      ]
  end

  defmodule Recalled do
    @moduledoc """
    Signal emitted when memory is recalled.

    ## Data Fields

    - `:agent_id` (required) - The agent whose memory was queried
    - `:query` (required) - The recall query used
    - `:count` (required) - Number of entries returned
    """

    use Jido.Signal,
      type: "memory.recalled",
      default_source: "/memory",
      schema: [
        agent_id: [type: :string, required: true, doc: "Agent whose memory was queried"],
        query: [type: :map, required: true, doc: "The recall query"],
        count: [type: :integer, required: true, doc: "Number of entries returned"]
      ]
  end

  defmodule Forgotten do
    @moduledoc """
    Signal emitted when memory entries are deleted.

    ## Data Fields

    - `:agent_id` (required) - The agent whose memory was modified
    - `:query` (required) - The forget query used
    - `:deleted` (required) - Number of entries deleted
    """

    use Jido.Signal,
      type: "memory.forgotten",
      default_source: "/memory",
      schema: [
        agent_id: [type: :string, required: true, doc: "Agent whose memory was modified"],
        query: [type: :map, required: true, doc: "The forget query"],
        deleted: [type: :integer, required: true, doc: "Number of entries deleted"]
      ]
  end
end
