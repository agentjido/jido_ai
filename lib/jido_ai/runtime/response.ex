defmodule Jido.AI.Runtime.Response do
  @moduledoc false

  # Some provider builders add an empty text marker after putting the assistant
  # message in response.context. Keep both views equal only for that exact,
  # lossless difference. Distinct unresolved tool messages must still fail.
  def align_context(
        %ReqLLM.Response{
          message:
            %ReqLLM.Message{
              role: :assistant,
              content: [%ReqLLM.Message.ContentPart{type: :text, text: ""}],
              tool_calls: calls
            } = message,
          context: %ReqLLM.Context{messages: messages} = context
        } = response
      )
      when is_list(calls) and calls != [] do
    case List.pop_at(messages, -1) do
      {%ReqLLM.Message{content: []} = previous, prefix} ->
        if previous == %{message | content: []},
          do: %{response | context: %{context | messages: prefix ++ [message]}},
          else: response

      _ ->
        response
    end
  end

  def align_context(response), do: response

  def event(response, state, request) do
    calls = ReqLLM.Response.tool_calls(response)

    Map.merge(
      %{
        call_id: state.llm_call_id,
        response_id: response.id,
        iteration: state.model_calls + 1,
        model: Jido.AI.Runtime.ModelCall.label(request.model),
        turn_type: if(request.schema != nil or calls == [], do: :final_answer, else: :tool_calls),
        text: ReqLLM.Response.text(response),
        content_parts: if(response.message, do: response.message.content, else: []),
        thinking_content: ReqLLM.Response.thinking(response),
        reasoning_details: if(response.message, do: response.message.reasoning_details),
        tool_calls: Enum.map(calls, &ReqLLM.ToolCall.to_map/1),
        usage: response.usage,
        finish_reason: response.finish_reason
      },
      Jido.AI.Reasoning.event(state)
    )
  end
end
