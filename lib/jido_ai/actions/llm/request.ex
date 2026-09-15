defmodule Jido.AI.Actions.LLM.Request do
  @moduledoc false
  alias Jido.AI.{ActionInput, Observe, Validation}
  alias Jido.AI.Actions.Helpers

  @defaults %{
    model: [:default_model, :model],
    max_tokens: [:default_max_tokens],
    temperature: [:default_temperature],
    system_prompt: [:default_system_prompt, :system_prompt]
  }

  def run(kind, action, params, context) do
    context = ActionInput.context(context)

    provided =
      case context[:provided_params] do
        keys when is_list(keys) -> keys
        _ -> Map.get(params, :__jido_ai_action_provided__, Map.keys(params))
      end

    keys =
      case kind do
        :embed -> [:model]
        :complete -> [:model, :max_tokens, :temperature]
        _ -> Map.keys(@defaults)
      end

    params =
      ActionInput.apply_defaults(action.schema(), params, context, Map.take(@defaults, keys), [
        :chat,
        :llm
      ])

    routed_model = Jido.AI.Capability.prepared(context, Jido.AI.Plugins.ModelRouting)

    params =
      if routed_model && not (:model in provided or "model" in provided) &&
           is_nil(get_in(context, [:jido_ai_request, :model])) do
        Map.put(params, :model, routed_model)
      else
        params
      end

    obs = context[:observability] || %{}

    metadata =
      Helpers.telemetry_metadata(
        context,
        kind,
        Map.merge(
          %{action: action.name(), model: value(params, :model)},
          measurements(kind, params)
        )
      )

    Observe.emit(obs, Observe.llm(:start), %{system_time: System.system_time()}, metadata)
    started = System.monotonic_time()

    with {:ok, params} <- Zoi.parse(action.schema(), params),
         {:ok, input, object_schema} <- input(kind, params),
         {:ok, model} <-
           Helpers.resolve_model(params[:model], if(kind == :embed, do: :embedding, else: :fast)),
         {:ok, options} <-
           ActionInput.options(
             params,
             context,
             if(kind == :embed, do: [:dimensions], else: [:max_tokens, :temperature])
           ),
         options =
           if(kind == :embed, do: Keyword.put(options, :return_usage, true), else: options),
         {:ok, response} <-
           Jido.AI.Runtime.ModelCall.request(
             request_kind(kind),
             model,
             input,
             options,
             object_schema,
             context
           ) do
      case validate_response(kind, response, object_schema) do
        :ok ->
          extra = if kind == :embed, do: %{dimensions: dimensions(response.embedding)}, else: %{}
          usage = Helpers.emit_llm_complete(obs, started, metadata, model, response, extra)
          {:ok, result(kind, response, model, usage)}

        {:error, reason} ->
          metadata = Map.merge(metadata, %{model: model, usage: Helpers.extract_usage(response)})
          fail(obs, started, metadata, reason)
      end
    else
      {:error, reason} -> fail(obs, started, metadata, reason)
    end
  end

  defp fail(obs, started, metadata, reason) do
    Helpers.emit_llm_error(obs, started, metadata, reason)
    {:error, Helpers.sanitize_error(reason)}
  end

  defp input(:embed, params) do
    texts =
      cond do
        not is_nil(params[:texts]) and not is_nil(params[:texts_list]) ->
          {:error, :ambiguous_embedding_texts}

        is_binary(params[:texts]) ->
          {:ok, [params.texts]}

        is_list(params[:texts_list]) and params.texts_list != [] ->
          {:ok, params.texts_list}

        true ->
          {:error, :texts_required}
      end

    with {:ok, texts} <- texts,
         :ok <-
           Enum.reduce_while(texts, :ok, fn text, :ok ->
             case Validation.validate_string(text, max_length: Validation.max_input_length()) do
               {:ok, _} -> {:cont, :ok}
               error -> {:halt, error}
             end
           end),
         do: {:ok, texts, nil}
  end

  defp input(kind, params) do
    params = if kind == :complete, do: Map.delete(params, :system_prompt), else: params

    with {:ok, params} <- Helpers.validate_and_sanitize_input(params),
         :ok <- object_schema(kind, params[:object_schema]),
         {:ok, context} <-
           ReqLLM.Context.normalize(
             params.prompt,
             if(params[:system_prompt], do: [system_prompt: params.system_prompt], else: [])
           ) do
      {:ok, context.messages, params[:object_schema]}
    end
  end

  defp object_schema(:generate_object, nil), do: {:error, :object_schema_required}
  defp object_schema(_, _), do: :ok

  defp validate_response(:generate_object, response, schema) when is_list(schema) do
    case ReqLLM.Schema.validate(response.object, schema) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp validate_response(:generate_object, response, schema) do
    with {:ok, output} <-
           Jido.AI.Output.new(schema: schema, on_validation_error: :error, retries: 0),
         {:ok, _} <- Jido.AI.Output.validate(output, response.object),
         do: :ok
  end

  defp validate_response(_, _, _), do: :ok
  defp request_kind(:embed), do: :embedding
  defp request_kind(:generate_object), do: :object
  defp request_kind(_), do: :text

  defp result(:embed, %{embedding: vectors}, model, _),
    do: %{
      embeddings: vectors,
      count: length(vectors),
      dimensions: dimensions(vectors),
      model: model
    }

  defp result(:generate_object, response, model, usage),
    do: %{object: response.object, model: model, usage: usage}

  defp result(_, response, model, usage),
    do: %{text: Helpers.extract_text(response), model: model, usage: usage}

  defp dimensions([]), do: 0
  defp dimensions([first | _]), do: length(first)
  defp value(map, key) when is_map(map), do: Map.get(map, key)
  defp value(_, _), do: nil

  defp measurements(:embed, params) do
    texts =
      (List.wrap(value(params, :texts)) ++ List.wrap(value(params, :texts_list)))
      |> Enum.filter(&is_binary/1)

    %{
      text_count: length(texts),
      total_text_length: Enum.reduce(texts, 0, &(String.length(&1) + &2))
    }
  end

  defp measurements(_, params) do
    prompt = value(params, :prompt)
    %{prompt_length: if(is_binary(prompt), do: String.length(prompt), else: 0)}
  end
end
