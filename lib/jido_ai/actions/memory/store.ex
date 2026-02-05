defmodule Jido.AI.Actions.Memory.Store do
  @moduledoc """
  Action to store a memory entry scoped to the current agent.

  The `agent_id` is automatically provided via tool context when used
  as a ReAct tool — the LLM does not need to specify it.

  ## Parameters

  - `key` (required) - Memory key
  - `value` (required) - Value to store (will be serialized as a string for LLM readability)
  - `tags` (optional) - List of tags for categorization
  - `metadata` (optional) - Arbitrary metadata map

  ## Returns

      %{stored: true, key: "user_name", tags: ["profile"]}
  """

  use Jido.Action,
    name: "memory_store",
    description: "Store a memory entry. Use this to remember facts, preferences, or any information for later recall.",
    category: "memory",
    tags: ["memory", "store"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        key: Zoi.string(description: "Memory key to store under"),
        value: Zoi.string(description: "Value to remember"),
        tags: Zoi.array(Zoi.string(), description: "Tags for categorization") |> Zoi.default([]),
        metadata: Zoi.map(description: "Additional metadata") |> Zoi.default(%{})
      })

  alias Jido.AI.Memory

  @impl Jido.Action
  def run(params, context) do
    agent_id = resolve_agent_id(context)

    case Memory.store(agent_id, params.key, params.value,
           tags: params.tags,
           metadata: params.metadata
         ) do
      {:ok, _entry} ->
        {:ok, %{stored: true, key: params.key, tags: params.tags}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_agent_id(context) when is_map(context) do
    Map.get(context, :agent_id) || "default"
  end

  defp resolve_agent_id(_), do: "default"
end
