defmodule Jido.AI.Reasoning.ReAct.Actions.StartRequest do
  @moduledoc "Initializes one request and appends its user message to the Session."

  alias Jido.AI.Thread.Projection

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/start-request",
    vsn: 1,
    name: "jido_ai_react_start_request",
    description: "Load conversation state and start one graph request",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(params, context) do
    now = System.system_time(:millisecond)
    tools = Jido.AI.Toolset.from_context(context)
    agent_state = Map.get(context, :agent_state, %{session: nil})
    session = session(agent_state, context, now)
    request_id = request_id(context)
    run_id = "run_#{Jido.generate_id()}"
    refs = %{request_id: request_id, run_id: run_id}

    with {:ok, session} <-
           Projection.append(session, %{role: :user, content: params.input}, refs, now) do
      {:ok,
       %{
         agent_state: Map.delete(agent_state, :session),
         session: Jido.Session.encode(session),
         request_id: request_id,
         run_id: run_id,
         started_at_ms: now,
         input: params.input,
         instructions: params.instructions,
         models: [params.model | params.fallback_models],
         model_index: 0,
         model_attempt: 0,
         model_calls: 0,
         max_model_calls: params.max_model_calls,
         max_retries: params.max_retries,
         retries: 0,
         options: params.options,
         prompt_cache: params.prompt_cache,
         stream: params.stream,
         review_tools: params.review_tools,
         repair_instruction: nil,
         context_window: params.context_window,
         tool_rounds: 0,
         max_tool_rounds: params.max_tool_rounds,
         tool_call_count: 0,
         tool_error_count: 0,
         max_tool_calls: params.max_tool_calls,
         tools: tools,
         model_outcome: nil,
         usage: Jido.AI.Usage.zero(),
         model_attempts: []
       }}
    end
  end

  defp session(%{session: %Jido.Session{} = session}, _context, _now), do: session

  defp session(_state, context, now) do
    agent_id = Map.get(context, :agent_id, Jido.generate_id())
    Jido.Session.new(id: "session:#{agent_id}", now: now)
  end

  defp request_id(%{signal: %{id: id}}) when is_binary(id), do: id
  defp request_id(_context), do: "request_#{Jido.generate_id()}"
end
