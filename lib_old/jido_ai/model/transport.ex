defmodule Jido.AI.Model.Transport do
  @moduledoc false

  @type kind :: :text | :embedding | :object | :stream | :stream_object

  @option_key :jido_ai_model_call
  @binder_key {__MODULE__, :option_binder}

  # An internal, process-local option binder captures live request options before
  # Request or a lazy Runner crosses a process boundary. Explicit call options
  # take precedence. No application configuration or shared registry is used.
  @doc false
  def put_option_binder(binder) when is_function(binder, 2) do
    Process.put(@binder_key, binder)
    :ok
  end

  @doc false
  def bind_options(input, options) do
    if has_call_option?(options) do
      options
    else
      case option_binder() do
        nil -> options
        binder -> binder.(input, options)
      end
    end
  end

  defp has_call_option?(options) when is_list(options),
    do: Keyword.keyword?(options) and Keyword.has_key?(options, @option_key)

  defp has_call_option?(options) when is_map(options),
    do: Map.has_key?(options, @option_key) or Map.has_key?(options, Atom.to_string(@option_key))

  defp has_call_option?(_), do: false

  defp option_binder do
    [self() | Process.get(:"$callers", [])]
    |> Enum.filter(&is_pid/1)
    |> Enum.uniq()
    |> Enum.find_value(fn owner ->
      case Process.info(owner, :dictionary) do
        {:dictionary, dictionary} ->
          case List.keyfind(dictionary, @binder_key, 0) do
            {_, binder} when is_function(binder, 2) -> binder
            _ -> nil
          end

        nil ->
          nil
      end
    end)
  end

  @doc false
  def request(kind, model, input, options, schema, context),
    do: Jido.AI.Quota.track(context, fn -> request(kind, model, input, options, schema) end)

  @doc false
  def request(kind, model, input, options, schema \\ nil) do
    {call, options} = Keyword.pop(bind_options(input, options), @option_key)

    # The callback receives the complete call and the default ReqLLM function.
    # It runs inside the same Exec lifetime and quota scope as the default path.
    case call do
      nil ->
        call_req_llm(kind, model, input, options, schema)

      call when is_function(call, 2) ->
        call.(%{kind: kind, model: model, input: input, options: options, schema: schema}, &call_req_llm/5)

      _ ->
        {:error, %{type: :invalid_model_call, message: "jido_ai_model_call must be a function of arity 2"}}
    end
  end

  defp call_req_llm(:text, model, messages, options, _schema),
    do: ReqLLM.generate_text(model, messages, options)

  defp call_req_llm(:embedding, model, texts, options, _schema),
    do: ReqLLM.embed(model, texts, options)

  defp call_req_llm(:object, model, messages, options, schema),
    do: ReqLLM.generate_object(model, messages, schema, options)

  defp call_req_llm(:stream, model, messages, options, _schema),
    do: ReqLLM.stream_text(model, messages, options)

  defp call_req_llm(:stream_object, model, messages, options, schema),
    do: ReqLLM.stream_object(model, messages, schema, options)
end
