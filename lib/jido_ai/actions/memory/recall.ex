defmodule Jido.AI.Actions.Memory.Recall do
  @moduledoc """
  Action to recall memory entries for the current agent.

  Supports recall by exact key or by tag matching. When recalling by tags,
  all specified tags must be present on the entry (AND semantics).

  ## Parameters

  - `key` (optional) - Recall a specific memory by key
  - `tags` (optional) - Recall all memories matching these tags

  At least one of `key` or `tags` must be provided.

  ## Returns

  By key:

      %{found: true, key: "user_name", value: "Alice", tags: ["profile"]}

  By tags:

      %{found: true, count: 2, entries: [%{key: "k1", value: "v1", tags: [...]}, ...]}
  """

  use Jido.Action,
    name: "memory_recall",
    description: "Recall stored memories. Look up by exact key or search by tags.",
    category: "memory",
    tags: ["memory", "recall", "search"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        key: Zoi.string(description: "Recall a specific memory by key") |> Zoi.optional(),
        tags:
          Zoi.array(Zoi.string(), description: "Recall memories matching all these tags")
          |> Zoi.optional()
      })

  alias Jido.AI.Memory

  @impl Jido.Action
  def run(%{key: key} = _params, context) when is_binary(key) do
    agent_id = resolve_agent_id(context)

    case Memory.recall(agent_id, %{key: key}) do
      {:ok, nil} ->
        {:ok, %{found: false, key: key}}

      {:ok, entry} ->
        {:ok, %{found: true, key: entry.key, value: entry.value, tags: entry.tags}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def run(%{tags: tags} = _params, context) when is_list(tags) do
    agent_id = resolve_agent_id(context)

    case Memory.recall(agent_id, %{tags: tags}) do
      {:ok, entries} ->
        formatted =
          Enum.map(entries, fn e ->
            %{key: e.key, value: e.value, tags: e.tags}
          end)

        {:ok, %{found: length(formatted) > 0, count: length(formatted), entries: formatted}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def run(_params, _context) do
    {:error, "At least one of 'key' or 'tags' must be provided"}
  end

  defp resolve_agent_id(context) when is_map(context) do
    Map.get(context, :agent_id) || "default"
  end

  defp resolve_agent_id(_), do: "default"
end
