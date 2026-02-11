defmodule Jido.AI.Actions.RLM.Orchestrate.LuaPlan do
  @moduledoc """
  LLM-generated Lua orchestration for context breakdown.

  Instead of the LLM choosing chunk_ids via tool-call JSON, it writes a short
  Lua script that inspects the chunk index and returns a structured plan.
  The Elixir runtime validates the plan, enforces budget caps, and executes
  it by delegating to `Agent.Spawn`.

  ## Lua Environment

  The following globals are injected into the Lua VM:

  * `query` — the parent query string
  * `chunks` — array of chunk descriptors: `{id, lines, byte_start, byte_end, size_bytes}`
  * `chunk_count` — number of chunks
  * `workspace_summary` — current workspace summary text
  * `budget` — table with `max_plan_items`, `max_total_chunks`, `current_depth`, `max_depth`

  ## Expected Return

  The Lua script must `return` an array of plan items:

      return {
        { chunk_ids = {"c_0", "c_1"}, query = "analyze auth flow" },
        { chunk_ids = {"c_5"},        query = "find error handling" }
      }

  If `query` is omitted from a plan item, the parent query is used.

  ## Parameters

  * `code` (required) — Lua code that returns a plan table
  * `projection_id` (optional) — chunk projection ID to inspect (defaults to active projection)
  * `execute` (optional, default `true`) — execute the plan or just validate and return it
  * `max_plan_items` (optional, default `10`) — max number of plan items
  * `max_total_chunks` (optional, default `30`) — max total chunk_ids across all items
  * `timeout_ms` (optional, default `500`) — Lua VM timeout
  * `spawn_timeout` (optional, default `120_000`) — per-child timeout when executing
  * `max_concurrency` (optional, default `5`) — max concurrent children when executing
  """

  use Jido.Action,
    name: "rlm_lua_plan",
    description:
      "Write Lua code to plan context breakdown into child agent tasks. " <>
        "The script receives chunks, query, workspace_summary, and budget as globals. " <>
        "Return an array of {chunk_ids = {...}, query = \"...\"} items.",
    category: "rlm",
    tags: ["rlm", "orchestrate", "lua", "planning"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        code: Zoi.string(),
        projection_id: Zoi.string() |> Zoi.optional(),
        execute: Zoi.boolean() |> Zoi.default(true),
        max_plan_items: Zoi.integer() |> Zoi.default(10),
        max_total_chunks: Zoi.integer() |> Zoi.default(30),
        timeout_ms: Zoi.integer() |> Zoi.default(500),
        spawn_timeout: Zoi.integer() |> Zoi.default(120_000),
        max_concurrency: Zoi.integer() |> Zoi.default(5)
      })

  alias Jido.AI.Actions.RLM.Agent.Spawn
  alias Jido.AI.RLM.ChunkProjection
  alias Jido.AI.RLM.WorkspaceStore

  @impl Jido.Action
  @spec run(map(), map()) :: {:ok, map()} | {:error, any()}
  def run(params, context) do
    defaults = Map.get(context, :chunk_defaults, %{})

    with {:ok, projection} <-
           ChunkProjection.ensure(
             context.workspace_ref,
             context.context_ref,
             %{projection_id: params[:projection_id]},
             defaults
           ) do
      globals = build_globals(params, context, projection)

      case eval_lua(params.code, globals, params[:timeout_ms] || 500) do
        {:ok, raw_plan} ->
          valid_ids = MapSet.new(Map.keys(projection.index))
          max_items = params[:max_plan_items] || 10
          max_chunks = params[:max_total_chunks] || 30

          case validate_plan(raw_plan, valid_ids, max_items, max_chunks, context[:query]) do
            {:ok, plan} ->
              if params[:execute] != false do
                results = execute_plan(plan, params, context, projection.id)

                WorkspaceStore.update(context.workspace_ref, fn ws ->
                  entry = %{projection_id: projection.id, plan: plan}
                  Map.update(ws, :lua_plans, [entry], &[entry | &1])
                end)

                {:ok, %{plan: plan, executed: true, results: results, projection_id: projection.id}}
              else
                {:ok, %{plan: plan, executed: false, projection_id: projection.id}}
              end

            {:error, reason} ->
              {:error, "Invalid Lua plan: #{reason}"}
          end

        {:error, reason} ->
          {:error, "Lua execution failed: #{reason}"}
      end
    end
  end

  defp build_globals(params, context, projection) do
    summary = WorkspaceStore.summary(context.workspace_ref)

    budget = %{
      "max_plan_items" => params[:max_plan_items] || 10,
      "max_total_chunks" => params[:max_total_chunks] || 30,
      "current_depth" => Map.get(context, :current_depth, 0),
      "max_depth" => Map.get(context, :max_depth, 2)
    }

    %{
      "query" => context[:query] || "",
      "chunks" =>
        Enum.map(projection.chunks, fn chunk ->
          %{
            "id" => chunk.id,
            "lines" => chunk.lines || "",
            "byte_start" => chunk.byte_start,
            "byte_end" => chunk.byte_end,
            "size_bytes" => chunk.size_bytes,
            "preview" => chunk.preview
          }
        end),
      "chunk_count" => projection.chunk_count,
      "workspace_summary" => summary,
      "budget" => budget
    }
  end

  defp eval_lua(code, globals, timeout_ms) do
    params = %{
      code: code,
      globals: globals,
      return_mode: :first,
      timeout_ms: timeout_ms,
      enable_unsafe_libs: false
    }

    case Jido.Tools.LuaEval.run(params, %{}) do
      {:ok, %{result: result}} -> {:ok, result}
      {:error, error} -> {:error, format_error(error)}
    end
  end

  defp format_error(%{message: msg}) when is_binary(msg), do: msg
  defp format_error(error), do: inspect(error)

  defp validate_plan(raw, valid_ids, max_items, max_chunks, default_query) do
    with {:ok, items} <- coerce_plan_list(raw),
         {:ok, items} <- validate_items(items, valid_ids, default_query),
         :ok <- check_limits(items, max_items, max_chunks) do
      {:ok, items}
    end
  end

  defp coerce_plan_list(items) when is_list(items) do
    {:ok, lua_array_to_list(items)}
  end

  defp coerce_plan_list(items) when is_map(items) do
    sorted =
      items
      |> Enum.sort_by(fn {k, _} -> to_sort_key(k) end)
      |> Enum.map(fn {_, v} -> v end)

    {:ok, sorted}
  end

  defp coerce_plan_list(_), do: {:error, "plan must be a table/array, got something else"}

  defp lua_array_to_list([{k, _} | _] = pairs) when is_integer(k) or is_float(k) do
    pairs
    |> Enum.sort_by(fn {k, _} -> to_sort_key(k) end)
    |> Enum.map(fn {_, v} -> v end)
  end

  defp lua_array_to_list(other), do: other

  defp to_sort_key(k) when is_integer(k), do: k
  defp to_sort_key(k) when is_float(k), do: round(k)
  defp to_sort_key(k) when is_binary(k), do: String.to_integer(k)
  defp to_sort_key(_), do: 0

  defp lua_table_to_map(pairs) when is_list(pairs) do
    Map.new(pairs, fn {k, v} -> {to_string(k), v} end)
  end

  defp lua_table_to_map(map) when is_map(map), do: map
  defp lua_table_to_map(other), do: other

  defp validate_items(items, valid_ids, default_query) do
    results =
      Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
        case validate_item(item, valid_ids, default_query) do
          {:ok, validated} -> {:cont, {:ok, [validated | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case results do
      {:ok, validated} -> {:ok, Enum.reverse(validated)}
      error -> error
    end
  end

  defp validate_item(item, valid_ids, default_query) when is_list(item) do
    validate_item(lua_table_to_map(item), valid_ids, default_query)
  end

  defp validate_item(item, valid_ids, default_query) when is_map(item) do
    raw_ids = item["chunk_ids"] || item[:chunk_ids]
    query = item["query"] || item[:query] || default_query || ""

    with {:ok, ids} <- coerce_chunk_ids(raw_ids),
         :ok <- check_ids_exist(ids, valid_ids) do
      {:ok, %{chunk_ids: ids, query: query}}
    end
  end

  defp validate_item(_, _valid_ids, _default_query) do
    {:error, "each plan item must be a table with chunk_ids and optional query"}
  end

  defp coerce_chunk_ids(ids) when is_list(ids) do
    values = lua_array_values(ids)
    {:ok, Enum.map(values, &to_string/1)}
  end

  defp coerce_chunk_ids(ids) when is_map(ids) do
    string_ids =
      ids
      |> Enum.sort_by(fn {k, _} -> to_sort_key(k) end)
      |> Enum.map(fn {_, v} -> to_string(v) end)

    {:ok, string_ids}
  end

  defp coerce_chunk_ids(nil), do: {:error, "chunk_ids is required"}
  defp coerce_chunk_ids(_), do: {:error, "chunk_ids must be an array of strings"}

  defp lua_array_values([{k, _} | _] = pairs) when is_integer(k) or is_float(k) do
    pairs
    |> Enum.sort_by(fn {k, _} -> to_sort_key(k) end)
    |> Enum.map(fn {_, v} -> v end)
  end

  defp lua_array_values(other), do: other

  defp check_ids_exist(ids, valid_ids) do
    invalid = Enum.reject(ids, &MapSet.member?(valid_ids, &1))

    if invalid == [] do
      :ok
    else
      {:error, "unknown chunk_ids: #{inspect(invalid)}"}
    end
  end

  defp check_limits(items, max_items, max_chunks) do
    if length(items) > max_items do
      {:error, "plan has #{length(items)} items, max is #{max_items}"}
    else
      total = items |> Enum.flat_map(& &1.chunk_ids) |> length()

      if total > max_chunks do
        {:error, "plan references #{total} total chunks, max is #{max_chunks}"}
      else
        :ok
      end
    end
  end

  defp execute_plan(plan, params, context, projection_id) do
    Enum.map(plan, fn %{chunk_ids: chunk_ids, query: query} ->
      spawn_params = %{
        chunk_ids: chunk_ids,
        query: query,
        projection_id: projection_id,
        timeout: params[:spawn_timeout] || 120_000,
        max_concurrency: params[:max_concurrency] || 5,
        max_chunk_bytes: 100_000
      }

      {:ok, result} = Spawn.run(spawn_params, context)
      %{status: :ok, query: query, chunk_ids: chunk_ids, result: result}
    end)
  end
end
