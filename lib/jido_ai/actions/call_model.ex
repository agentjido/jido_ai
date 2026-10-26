defmodule Jido.AI.Actions.CallModel do
  @moduledoc """
  Calls one text model from portable messages.
  """

  use Jido.Action,
    name: "jido_ai_call_model",
    description: "Call one text model",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(params, _context) do
    messages = Enum.map(params.messages, &to_req_llm_message/1)
    context = ReqLLM.Context.new(messages)
    options = Map.to_list(params.options)

    with {:ok, tools} <- Jido.AI.ToolRegistry.definitions(params.allowed_tools),
         {:ok, response} <-
           ReqLLM.generate_text(params.model, context, Keyword.put(options, :tools, tools)) do
      outcome = ReqLLM.Response.classify(response)
      assistant = portable_assistant(outcome)

      {:ok,
       %{
         allowed_tools: params.allowed_tools,
         history: params.history ++ [assistant],
         input: params.input,
         iteration: params.iteration + 1,
         kind: outcome.type,
         max_iterations: params.max_iterations,
         max_tool_calls: params.max_tool_calls,
         text: outcome.text,
         tool_call_count: params.tool_call_count,
         tool_calls: outcome.tool_calls
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp to_req_llm_message(%{role: :system, content: content}),
    do: ReqLLM.Context.system(content)

  defp to_req_llm_message(%{role: :user, content: content}),
    do: ReqLLM.Context.user(content)

  defp to_req_llm_message(%{role: :assistant, content: content, tool_calls: calls}) do
    tool_calls =
      Enum.map(calls, fn call ->
        ReqLLM.ToolCall.new(call.id, call.name, Jason.encode!(call.arguments))
      end)

    ReqLLM.Context.assistant(content, tool_calls: tool_calls)
  end

  defp to_req_llm_message(%{role: :assistant, content: content}),
    do: ReqLLM.Context.assistant(content)

  defp to_req_llm_message(%{
         role: :tool,
         name: name,
         tool_call_id: tool_call_id,
         output: output
       }) do
    ReqLLM.Context.tool_result_message(name, tool_call_id, output)
  end

  defp portable_assistant(outcome) do
    %{
      role: :assistant,
      content: outcome.text,
      tool_calls: Enum.map(outcome.tool_calls, &Map.take(&1, [:id, :name, :arguments]))
    }
  end
end
