defmodule Jido.AI.Reasoning.ReAct.Actions.Collect do
  @moduledoc """
  Collect a terminal result from ReAct events or a checkpoint token.
  """

  alias Jido.AI.Query

  use Jido.Action,
    name: "react_collect",
    description: "Collect terminal output from ReAct runtime events/checkpoint",
    schema:
      Zoi.object(%{
        events: Zoi.any() |> Zoi.optional(),
        checkpoint_token: Zoi.string() |> Zoi.optional(),
        run_until_terminal?: Zoi.boolean() |> Zoi.default(true),
        query: Query.schema() |> Zoi.optional(),
        model: Zoi.any() |> Zoi.optional(),
        system_prompt: Zoi.string() |> Zoi.optional(),
        tools: Zoi.any() |> Zoi.optional(),
        allowed_tools: Zoi.list(Zoi.string()) |> Zoi.optional(),
        request_transformer: Zoi.atom() |> Zoi.optional(),
        max_iterations: Zoi.integer() |> Zoi.default(10),
        max_tokens: Zoi.integer() |> Zoi.default(4096),
        temperature: Zoi.float() |> Zoi.default(0.2),
        llm_opts: Zoi.any() |> Zoi.optional(),
        llm_timeout_ms: Zoi.integer() |> Zoi.optional(),
        req_http_options: Zoi.list(Zoi.any()) |> Zoi.optional(),
        stream_timeout_ms: Zoi.integer() |> Zoi.optional(),
        tool_heartbeat_ms: Zoi.integer() |> Zoi.optional(),
        tool_timeout_ms: Zoi.integer() |> Zoi.default(15_000),
        tool_max_retries: Zoi.integer() |> Zoi.default(1),
        tool_retry_backoff_ms: Zoi.integer() |> Zoi.default(200),
        tool_concurrency: Zoi.integer() |> Zoi.default(4),
        stream_content: Zoi.boolean() |> Zoi.default(false),
        store_content: Zoi.boolean() |> Zoi.default(false),
        stream_reasoning: Zoi.boolean() |> Zoi.default(false),
        store_reasoning: Zoi.boolean() |> Zoi.default(false),
        token_secret: Zoi.string() |> Zoi.optional(),
        token_ttl_ms: Zoi.integer() |> Zoi.optional(),
        token_compress?: Zoi.boolean() |> Zoi.default(false),
        task_supervisor: Zoi.any() |> Zoi.optional(),
        limits: Zoi.map() |> Zoi.optional(),
        runtime_context: Zoi.map() |> Zoi.optional()
      })

  alias Jido.AI.Reasoning.ReAct
  alias Jido.AI.Reasoning.ReAct.Actions.Helpers

  def category, do: "ai"
  def tags, do: ["react", "runtime", "collect"]
  def vsn, do: "1.0.0"

  @impl Jido.Action
  def on_before_validate_params(params),
    do: {:ok, Jido.AI.SchemaInput.normalize(schema(), params)}

  @impl Jido.Action
  def run(params, context) do
    config = Helpers.build_config(params, context)

    case {params[:events], params[:checkpoint_token]} do
      {events, _token} when not is_nil(events) ->
        ReAct.collect(events, config, [])

      {nil, token} when is_binary(token) ->
        opts =
          Helpers.build_runner_opts(params, context)
          |> Keyword.put(:run_until_terminal?, params[:run_until_terminal?] != false)
          |> maybe_put_query(params[:query])

        ReAct.collect(token, config, opts)

      _ ->
        {:error, :events_or_checkpoint_token_required}
    end
  end

  defp maybe_put_query(opts, nil), do: opts
  defp maybe_put_query(opts, query), do: Keyword.put(opts, :query, query)
end
