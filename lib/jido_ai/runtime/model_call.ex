defmodule Jido.AI.Runtime.ModelCall do
  @moduledoc false

  @type kind :: :text | :embedding | :object | :stream | :stream_object

  @doc false
  def request(kind, model, input, options, schema, context),
    do: Jido.AI.Quota.track(context, fn -> request(kind, model, input, options, schema) end)

  @doc false
  def request(kind, model, input, options, schema \\ nil) do
    case Jido.AI.Test.ReActScript.request(kind, input, options, fn scripted_model, scripted_options ->
           call_req_llm(kind, scripted_model, input, scripted_options, schema)
         end) do
      :not_scripted -> call_req_llm(kind, model, input, options, schema)
      scripted -> scripted
    end
  end

  @doc false
  def label(model) when is_atom(model), do: model |> Jido.AI.Models.resolve() |> label()
  def label(model) when is_binary(model), do: model

  def label(model) do
    case ReqLLM.model(model) do
      {:ok, %LLMDB.Model{} = normalized} -> format_label(normalized)
      _ -> inspect(model)
    end
  end

  @doc false
  def fingerprint_segment(model) when is_atom(model),
    do: model |> Jido.AI.Models.resolve() |> fingerprint_segment()

  def fingerprint_segment(model) when is_binary(model), do: model

  def fingerprint_segment(model) do
    model
    |> normalized_fingerprint_term()
    |> :erlang.term_to_binary([:deterministic])
    |> Base.url_encode64(padding: false)
  end

  @doc false
  def provider_option_keys(model) do
    with {:ok, %LLMDB.Model{} = normalized} <- ReqLLM.model(Jido.AI.Models.resolve(model)),
         provider when is_atom(provider) <- normalized.provider,
         {:ok, provider_module} <- ReqLLM.provider(provider),
         true <- function_exported?(provider_module, :provider_schema, 0) do
      provider_module.provider_schema().schema
      |> Keyword.keys()
      |> Map.new(&{Atom.to_string(&1), &1})
    else
      _ -> %{}
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

  defp format_label(%LLMDB.Model{} = model) do
    model_id = model.model || model.id

    if (is_atom(model.provider) or is_binary(model.provider)) and is_binary(model_id),
      do: "#{model.provider}:#{model_id}",
      else: inspect(model)
  end

  defp normalized_fingerprint_term(model) do
    case ReqLLM.model(model) do
      {:ok, %LLMDB.Model{} = normalized} ->
        normalized
        |> Map.from_struct()
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      _ ->
        model
    end
  end
end
