defmodule Jido.AI.Actions.RLM.Agent.Spawn do
  @moduledoc """
  Spawn child RLM agents to explore context subsets with multi-step reasoning.

  Unlike `SubqueryBatch`, which fans out a single LLM prompt to many chunks,
  this action spawns full child agents that can run their own multi-step
  reasoning loops (tool calls, re-reads, sub-queries) over each chunk.
  Use this when the per-chunk analysis is too complex for a single LLM call.

  ## Depth degradation

  To prevent unbounded recursion, the action reads `current_depth` and
  `max_depth` from the execution context. When `current_depth >= max_depth`,
  it degrades to flat `generate_text` calls identical to `SubqueryBatch`,
  avoiding further agent spawning.

  ## Parameters

  * `chunk_ids` (required) - List of chunk identifiers to process
  * `query` (required) - The query to explore across chunks
  * `projection_id` (optional) - Chunk projection ID to read chunk boundaries from
  * `max_iterations` (optional) - Max iterations for each child agent (default: `8`)
  * `model` (optional) - Model override for degraded flat calls
  * `timeout` (optional) - Per-child timeout in milliseconds (default: `120_000`)
  * `max_concurrency` (optional) - Maximum concurrent child agents (default: `5`)
  * `max_chunk_bytes` (optional) - Maximum bytes to read from each chunk (default: `100_000`)

  ## Examples

      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.RLM.Agent.Spawn,
        %{chunk_ids: ["c_0", "c_1"], query: "Explain the authentication flow"},
        %{workspace_ref: ref, context_ref: ctx_ref, current_depth: 0, max_depth: 3}
      )
  """

  use Jido.Action,
    name: "rlm_spawn_agent",
    description: "Spawn child RLM agents to explore context subsets with multi-step reasoning",
    category: "rlm",
    tags: ["rlm", "agent", "spawn", "recursive"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        chunk_ids: Zoi.list(Zoi.string()),
        query: Zoi.string(),
        projection_id: Zoi.string() |> Zoi.optional(),
        max_iterations: Zoi.integer() |> Zoi.default(8),
        model: Zoi.string() |> Zoi.optional(),
        timeout: Zoi.integer() |> Zoi.default(120_000),
        max_concurrency: Zoi.integer() |> Zoi.default(5),
        max_chunk_bytes: Zoi.integer() |> Zoi.default(100_000)
      })

  alias Jido.AI.RLM.{BudgetStore, ChunkProjection, ContextStore, PartialCollector, WorkspaceStore}

  @impl Jido.Action
  @spec run(map(), map()) :: {:ok, map()}
  def run(params, context) do
    current_depth = Map.get(context, :current_depth, 0)
    max_depth = Map.get(context, :max_depth, 2)
    budget_ref = Map.get(context, :budget_ref)
    defaults = Map.get(context, :chunk_defaults, %{})

    with {:ok, projection} <-
           ChunkProjection.ensure(
             context.workspace_ref,
             context.context_ref,
             %{projection_id: params[:projection_id]},
             defaults
           ) do
      {chunk_ids, skipped} = apply_budget(budget_ref, params.chunk_ids)
      params = %{params | chunk_ids: chunk_ids}

      results =
        if current_depth >= max_depth do
          run_flat(params, projection, context)
        else
          run_recursive(params, projection, context, current_depth, max_depth)
        end

      {successes, errors} = Enum.split_with(results, &(&1.status == :ok))

      :ok =
        WorkspaceStore.update(context.workspace_ref, fn ws ->
          Map.update(ws, :spawn_results, results, &(results ++ &1))
        end)

      {:ok,
       %{
         completed: length(successes),
         errors: length(errors),
         skipped: skipped,
         results: Enum.map(successes, &Map.take(&1, [:chunk_id, :answer, :summary])),
         projection_id: projection.id
       }}
    end
  end

  @doc false
  @spec fetch_chunk_text(String.t(), ChunkProjection.projection(), ContextStore.context_ref(), non_neg_integer()) ::
          String.t()
  def fetch_chunk_text(chunk_id, projection, context_ref, max_bytes) do
    case ChunkProjection.lookup_chunk(projection, chunk_id) do
      {:ok, chunk_meta} ->
        byte_start = chunk_meta.byte_start
        length = min(chunk_meta.byte_end - byte_start, max_bytes)

        case ContextStore.fetch_range(context_ref, byte_start, length) do
          {:ok, text} -> text
          _ -> ""
        end

      {:error, :chunk_not_found} ->
        ""
    end
  end

  defp run_flat(params, projection, context) do
    model = params[:model] || context[:recursive_model] || "anthropic:claude-haiku-4-5"
    collector_pid = maybe_start_collector(context)

    try do
      params.chunk_ids
      |> Task.async_stream(
        fn chunk_id ->
          text = fetch_chunk_text(chunk_id, projection, context.context_ref, params.max_chunk_bytes)
          run_flat_query(model, params.query, text, chunk_id)
        end,
        max_concurrency: params.max_concurrency,
        timeout: params.timeout,
        on_timeout: :kill_task
      )
      |> Enum.map(&normalize_result/1)
    after
      maybe_stop_collector(collector_pid)
    end
  end

  defp run_recursive(params, projection, context, current_depth, max_depth) do
    child_mod = context[:child_agent] || Jido.AI.RLM.ChildAgent
    jido_instance = Map.get(context, :jido)
    budget_ref = Map.get(context, :budget_ref)
    collector_pid = maybe_start_collector(context)

    child_tool_ctx =
      %{
        current_depth: current_depth + 1,
        max_depth: max_depth,
        child_agent: child_mod,
        jido: jido_instance
      }
      |> maybe_put(:budget_ref, budget_ref)
      |> maybe_put(:partial_sink_pid, collector_pid)

    try do
      params.chunk_ids
      |> Task.async_stream(
        fn chunk_id ->
          text = fetch_chunk_text(chunk_id, projection, context.context_ref, params.max_chunk_bytes)
          run_child_agent(child_mod, chunk_id, text, params.query, child_tool_ctx, params.timeout, jido_instance)
        end,
        max_concurrency: params.max_concurrency,
        timeout: params.timeout,
        on_timeout: :kill_task
      )
      |> Enum.map(&normalize_result/1)
    after
      maybe_stop_collector(collector_pid)
    end
  end

  defp run_child_agent(child_mod, chunk_id, chunk_text, query, child_tool_ctx, timeout, jido_instance) do
    start_opts =
      if jido_instance,
        do: [agent: child_mod, jido: jido_instance],
        else: [agent: child_mod]

    {:ok, pid} = Jido.AgentServer.start(start_opts)

    try do
      case child_mod.explore_sync(pid, query,
             context: chunk_text,
             tool_context: child_tool_ctx,
             timeout: timeout
           ) do
        {:ok, result} ->
          answer = extract_text(result)
          summary = String.slice(String.trim(answer), 0, 300)
          %{status: :ok, chunk_id: chunk_id, answer: answer, summary: summary}

        {:error, reason} ->
          %{status: :error, chunk_id: chunk_id, error: inspect(reason)}
      end
    after
      try do
        GenServer.stop(pid, :normal, 5_000)
      catch
        :exit, _ -> :ok
      end
    end
  end

  defp run_flat_query(model, query, chunk_text, chunk_id) do
    messages = [
      %{role: "user", content: "#{query}\n\n---\n\n#{chunk_text}"}
    ]

    case ReqLLM.Generation.generate_text(model, messages, []) do
      {:ok, response} ->
        answer = extract_text(response)
        summary = String.slice(String.trim(answer), 0, 300)
        %{status: :ok, chunk_id: chunk_id, answer: answer, summary: summary}

      {:error, reason} ->
        %{status: :error, chunk_id: chunk_id, error: inspect(reason)}
    end
  end

  defp normalize_result({:ok, result}), do: result
  defp normalize_result({:exit, :timeout}), do: %{status: :error, chunk_id: nil, error: "timeout"}
  defp normalize_result({:exit, reason}), do: %{status: :error, chunk_id: nil, error: inspect(reason)}

  defp extract_text(%{text: text}) when is_binary(text), do: text
  defp extract_text(%{message: %{content: content}}) when is_binary(content), do: content

  defp extract_text(%{message: %{content: content}}) when is_list(content) do
    Jido.AI.Text.extract_from_content(content) || ""
  end

  defp extract_text(%{choices: [%{message: %{content: text}} | _]}) when is_binary(text), do: text
  defp extract_text(response) when is_binary(response), do: response
  defp extract_text(_), do: ""

  defp apply_budget(nil, chunk_ids), do: {chunk_ids, 0}

  defp apply_budget(budget_ref, chunk_ids) do
    total = length(chunk_ids)
    {:ok, granted, _remaining} = BudgetStore.reserve_children(budget_ref, total)
    {Enum.take(chunk_ids, granted), total - granted}
  end

  defp maybe_start_collector(%{workspace_ref: workspace_ref}) when workspace_ref != nil do
    case PartialCollector.start_link(workspace_ref) do
      {:ok, pid} -> pid
      _ -> nil
    end
  end

  defp maybe_start_collector(_context), do: nil

  defp maybe_stop_collector(nil), do: :ok
  defp maybe_stop_collector(pid), do: PartialCollector.stop(pid)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
