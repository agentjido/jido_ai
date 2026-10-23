defmodule Jido.AI.Test.ReqLLMMock do
  @moduledoc false

  @default_response_id "req-llm-mock-response"

  @doc false
  def install!, do: Mimic.copy(ReqLLM)

  @doc false
  def text_response(model, context, text, attrs \\ [])
      when is_binary(model) and is_binary(text) and is_list(attrs) do
    response(model, context, ReqLLM.Context.assistant(text), attrs)
  end

  @doc false
  def tool_response(model, context, calls, attrs \\ [])
      when is_binary(model) and is_list(calls) and is_list(attrs) do
    message = ReqLLM.Context.assistant("", tool_calls: calls)
    response(model, ReqLLM.Context.append(context, message), message, attrs)
  end

  @doc false
  def object_response(model, context, object, attrs \\ [])
      when is_binary(model) and is_map(object) and is_list(attrs) do
    text_response(model, context, "", Keyword.put(attrs, :object, object))
  end

  defp response(model, context, message, attrs) do
    defaults = %ReqLLM.Response{
      id: @default_response_id,
      model: model,
      context: context,
      message: message
    }

    struct!(defaults, attrs)
  end
end
