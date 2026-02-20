defmodule Jido.AI.Reasoning.ReAct.Actions.Start do
  @moduledoc """
  Start a ReAct runtime execution and return an event stream.
  """

  use Jido.Action,
    name: "react_start",
    description: "Start a Task-based ReAct runtime stream",
    category: "ai",
    tags: ["react", "runtime", "streaming"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        query: Zoi.string(description: "User query for ReAct execution"),
        request_id: Zoi.string() |> Zoi.optional(),
        run_id: Zoi.string() |> Zoi.optional(),
        model: Zoi.any() |> Zoi.optional(),
        system_prompt: Zoi.string() |> Zoi.optional(),
        tools: Zoi.any() |> Zoi.optional(),
        max_iterations: Zoi.integer() |> Zoi.default(10),
        max_tokens: Zoi.integer() |> Zoi.default(1024),
        temperature: Zoi.float() |> Zoi.default(0.2),
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
  alias Jido.AI.Validation

  @impl Jido.Action
  def run(params, context) do
    with {:ok, _} <- Validation.validate_string(params[:query], max_length: Validation.max_input_length()) do
      config = Helpers.build_config(params, context)
      opts = Helpers.build_runner_opts(params, context)
      request_id = params[:request_id] || "req_#{Jido.Util.generate_id()}"
      run_id = params[:run_id] || "run_#{Jido.Util.generate_id()}"

      events = ReAct.stream(params[:query], config, Keyword.merge(opts, request_id: request_id, run_id: run_id))

      {:ok,
       %{
         run_id: run_id,
         request_id: request_id,
         events: events,
         checkpoint_token: nil
       }}
    else
      {:error, :empty_string} -> {:error, :query_required}
      {:error, reason} -> {:error, reason}
    end
  end
end
