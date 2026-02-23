defmodule Jido.AI.Reasoning.ReAct.Actions.Continue do
  @moduledoc """
  Continue a ReAct runtime execution from a signed checkpoint token.
  """

  use Jido.Action,
    name: "react_continue",
    description: "Resume a Task-based ReAct runtime stream from checkpoint token",
    category: "ai",
    tags: ["react", "runtime", "streaming", "checkpoint"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        checkpoint_token: Zoi.string(description: "Signed ReAct checkpoint token"),
        query: Zoi.string() |> Zoi.optional(),
        model: Zoi.any() |> Zoi.optional(),
        system_prompt: Zoi.string() |> Zoi.optional(),
        tools: Zoi.any() |> Zoi.optional(),
        max_iterations: Zoi.integer() |> Zoi.default(10),
        max_tokens: Zoi.integer() |> Zoi.default(1024),
        temperature: Zoi.float() |> Zoi.default(0.2),
        llm_opts: Zoi.any() |> Zoi.optional(),
        llm_timeout_ms: Zoi.integer() |> Zoi.optional(),
        req_http_options: Zoi.list(Zoi.any()) |> Zoi.optional(),
        tool_timeout_ms: Zoi.integer() |> Zoi.default(15_000),
        tool_max_retries: Zoi.integer() |> Zoi.default(1),
        tool_retry_backoff_ms: Zoi.integer() |> Zoi.default(200),
        tool_concurrency: Zoi.integer() |> Zoi.default(4),
        emit_signals?: Zoi.boolean() |> Zoi.default(true),
        emit_telemetry?: Zoi.boolean() |> Zoi.default(true),
        redact_tool_args?: Zoi.boolean() |> Zoi.default(true),
        capture_deltas?: Zoi.boolean() |> Zoi.default(true),
        capture_thinking?: Zoi.boolean() |> Zoi.default(true),
        capture_messages?: Zoi.boolean() |> Zoi.default(true),
        token_secret: Zoi.string() |> Zoi.optional(),
        token_ttl_ms: Zoi.integer() |> Zoi.optional(),
        token_compress?: Zoi.boolean() |> Zoi.default(false),
        task_supervisor: Zoi.any() |> Zoi.optional(),
        runtime_context: Zoi.map() |> Zoi.optional()
      })

  alias Jido.AI.Reasoning.ReAct.Actions.Helpers
  alias Jido.AI.Reasoning.ReAct

  @impl Jido.Action
  def run(params, context) do
    config = Helpers.build_config(params, context)

    opts =
      params
      |> Helpers.build_runner_opts(context)
      |> maybe_put_query(params[:query])

    ReAct.continue(params[:checkpoint_token], config, opts)
  end

  defp maybe_put_query(opts, nil), do: opts
  defp maybe_put_query(opts, query), do: Keyword.put(opts, :query, query)
end
