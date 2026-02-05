defmodule Jido.AI.Actions.Memory.Forget do
  @moduledoc """
  Action to forget (delete) memory entries for the current agent.

  Supports deletion by exact key or by tag matching.

  ## Parameters

  - `key` (optional) - Forget a specific memory by key
  - `tags` (optional) - Forget all memories matching these tags

  At least one of `key` or `tags` must be provided.

  ## Returns

      %{forgotten: true, deleted: 1}
  """

  use Jido.Action,
    name: "memory_forget",
    description: "Forget stored memories. Delete by exact key or by matching tags.",
    category: "memory",
    tags: ["memory", "forget", "delete"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        key: Zoi.string(description: "Forget a specific memory by key") |> Zoi.optional(),
        tags:
          Zoi.array(Zoi.string(), description: "Forget memories matching all these tags")
          |> Zoi.optional()
      })

  alias Jido.AI.Memory

  @impl Jido.Action
  def run(%{key: key} = _params, context) when is_binary(key) do
    agent_id = resolve_agent_id(context)

    case Memory.forget(agent_id, %{key: key}) do
      {:ok, count} ->
        {:ok, %{forgotten: true, deleted: count}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def run(%{tags: tags} = _params, context) when is_list(tags) do
    agent_id = resolve_agent_id(context)

    case Memory.forget(agent_id, %{tags: tags}) do
      {:ok, count} ->
        {:ok, %{forgotten: true, deleted: count}}

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
