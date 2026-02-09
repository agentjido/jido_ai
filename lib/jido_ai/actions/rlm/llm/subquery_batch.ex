defmodule Jido.AI.Actions.RLM.LLM.SubqueryBatch do
  @moduledoc """
  Run a sub-LLM query across multiple chunks concurrently.

  Fans out a prompt to each specified chunk, collects results, and stores
  them in the workspace under `:subquery_results`. Useful for map-reduce
  style analysis where the same question is asked of many context windows.

  ## Parameters

  * `chunk_ids` (required) - List of chunk identifiers to process
  * `prompt` (required) - The prompt template to apply to each chunk
  * `model` (optional) - Model spec override (defaults to context's recursive model or `"anthropic:claude-haiku-4-5"`)
  * `max_concurrency` (optional) - Maximum concurrent sub-queries (default: `10`)
  * `timeout` (optional) - Per-chunk timeout in milliseconds (default: `60_000`)
  * `max_chunk_bytes` (optional) - Maximum bytes to read from each chunk (default: `50_000`)

  ## Examples

      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.RLM.LLM.SubqueryBatch,
        %{chunk_ids: ["c_0", "c_1"], prompt: "Summarize this section"},
        %{workspace_ref: ref, context_ref: ctx_ref}
      )
  """

  use Jido.Action,
    name: "llm_subquery_batch",
    description: "Run a sub-LLM query across multiple chunks concurrently. Use for map-reduce style analysis.",
    category: "rlm",
    tags: ["rlm", "llm", "subquery", "batch"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        chunk_ids: Zoi.list(Zoi.string()),
        prompt: Zoi.string(),
        model: Zoi.string() |> Zoi.optional(),
        max_concurrency: Zoi.integer() |> Zoi.default(10),
        timeout: Zoi.integer() |> Zoi.default(60_000),
        max_chunk_bytes: Zoi.integer() |> Zoi.default(50_000)
      })

  alias Jido.AI.RLM.{ContextStore, WorkspaceStore}

  @impl Jido.Action
  @spec run(map(), map()) :: {:ok, map()}
  def run(params, context) do
    model = params[:model] || context[:recursive_model] || "anthropic:claude-haiku-4-5"
    workspace = WorkspaceStore.get(context.workspace_ref)

    results =
      params.chunk_ids
      |> Task.async_stream(
        fn chunk_id ->
          text = fetch_chunk_text(chunk_id, workspace, context.context_ref, params.max_chunk_bytes)
          run_subquery(model, params.prompt, text, chunk_id)
        end,
        max_concurrency: params.max_concurrency,
        timeout: params.timeout,
        on_timeout: :kill_task
      )
      |> Enum.map(&normalize_result/1)

    {successes, errors} = Enum.split_with(results, &(&1.status == :ok))

    :ok =
      WorkspaceStore.update(context.workspace_ref, fn ws ->
        Map.update(ws, :subquery_results, results, &(results ++ &1))
      end)

    {:ok,
     %{
       completed: length(successes),
       errors: length(errors),
       results: Enum.map(successes, &Map.take(&1, [:chunk_id, :answer]))
     }}
  end

  @doc false
  @spec fetch_chunk_text(String.t(), map(), ContextStore.context_ref(), non_neg_integer()) ::
          String.t()
  def fetch_chunk_text(chunk_id, workspace, context_ref, max_bytes) do
    case get_in(workspace, [:chunks, :index, chunk_id]) do
      nil ->
        ""

      chunk_meta ->
        byte_start = chunk_meta.byte_start
        length = min(chunk_meta.byte_end - byte_start, max_bytes)

        case ContextStore.fetch_range(context_ref, byte_start, length) do
          {:ok, text} -> text
          _ -> ""
        end
    end
  end

  defp run_subquery(model, prompt, chunk_text, chunk_id) do
    messages = [
      %{role: "user", content: "#{prompt}\n\n---\n\n#{chunk_text}"}
    ]

    case ReqLLM.Generation.generate_text(model, messages, []) do
      {:ok, response} ->
        answer = extract_text(response)
        %{status: :ok, chunk_id: chunk_id, answer: answer}

      {:error, reason} ->
        %{status: :error, chunk_id: chunk_id, error: inspect(reason)}
    end
  end

  defp normalize_result({:ok, result}), do: result
  defp normalize_result({:exit, :timeout}), do: %{status: :error, chunk_id: nil, error: "timeout"}
  defp normalize_result({:exit, reason}), do: %{status: :error, chunk_id: nil, error: inspect(reason)}

  defp extract_text(%{text: text}), do: text
  defp extract_text(%{choices: [%{message: %{content: text}} | _]}), do: text
  defp extract_text(response) when is_binary(response), do: response
  defp extract_text(_), do: ""
end
