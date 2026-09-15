defmodule Jido.AI.Runtime.RequestTransform do
  @moduledoc false
  alias Jido.AI.{Models, Output, Profile, ToolCatalog}
  alias Jido.AI.Reasoning.ReAct.{Config, State}

  def prepare(state, request, context) do
    catalog = Jido.AI.Reasoning.tools(state)

    case state.profile.reasoning[:request_transformer] do
      nil ->
        {:ok, request, catalog}

      module ->
        case transform(module, state, request, catalog, context) do
          {:error, _} = error ->
            :ok = Jido.AI.Orchestration.failure_type(context, :request_transform)
            error

          result ->
            result
        end
    end
  end

  defp transform(module, state, request, catalog, context) do
    tools = Map.new(catalog, &{&1.name, &1.target})

    input = %{
      messages: Map.get(request, :public_messages, messages(request.messages)),
      model: request.model,
      llm_opts: request.options,
      tools: tools
    }

    config = config(state, context)
    view = state_view(state, context)

    runtime_context =
      context
      |> then(&Jido.AI.Runtime.ToolInterception.context(state, &1))
      |> Map.put(:request_id, view.request_id)
      |> Map.put(:run_id, view.run_id)
      |> Map.put(:query, latest_query(view.context))

    with {:ok, overrides} <- invoke(module, input, view, config, runtime_context),
         {:ok, overrides} <-
           Profile.fields(
             overrides,
             [:messages, :model, :llm_opts, :tools],
             "request_transformer"
           ),
         model =
           if(overrides[:model], do: Models.resolve(overrides.model), else: request.model),
         {:ok, selected} <- select(catalog, overrides[:tools], state, context),
         llm_opts = Jido.AI.Model.Options.merge(request.options, overrides[:llm_opts], model),
         raw_messages = overrides[:messages] || input.messages,
         true <- is_list(raw_messages),
         raw_messages =
           if(state.repairs == 0 and Map.has_key?(overrides, :messages),
             do: Output.apply_instructions(raw_messages, state.output),
             else: raw_messages
           ),
         {:ok, messages} <- Jido.AI.Model.Messages.normalize_messages(raw_messages) do
      selected = if Jido.AI.Reasoning.tools_disabled?(state), do: [], else: selected
      opts = synchronize(llm_opts, selected, state.repairs > 0)

      schema =
        if selected == [],
          do: Jido.AI.Reasoning.provider_schema(state.profile, state.output),
          else: nil

      {:ok,
       request
       |> Map.merge(%{
         model: model,
         options: opts,
         messages: messages,
         schema: schema,
         public_messages: raw_messages
       }), selected}
    else
      false -> {:error, :invalid_request_messages}
      {:error, _} = error -> error
    end
  rescue
    error ->
      {:error, {:request_transformer_exception, %{error: Exception.message(error), type: error.__struct__}}}
  end

  defp invoke(module, input, state, config, context) do
    case module.transform_request(input, state, config, context) do
      {:ok, overrides} when is_map(overrides) and not is_struct(overrides) -> {:ok, overrides}
      {:error, reason} -> {:error, {:request_transformer, reason}}
      other -> {:error, {:invalid_request_transformer_result, other}}
    end
  catch
    kind, reason -> {:error, {:request_transformer, {kind, reason}}}
  end

  defp select(catalog, nil, _, _), do: {:ok, catalog}

  defp select(catalog, selected, _state, context)
       when is_map(selected) and not is_struct(selected) do
    current = Map.new(catalog, &{&1.name, &1})

    selected
    |> Enum.sort_by(&elem(&1, 0))
    |> Profile.traverse(fn {name, target} ->
      case current[name] do
        %{target: ^target} = tool ->
          {:ok, tool}

        _ ->
          defaults = Map.get(context, :jido_ai_tool_defaults, %{})

          with {:ok, [tool]} <-
                 ToolCatalog.new([Map.merge(defaults, %{name: name, target: target})]),
               do: {:ok, tool}
      end
    end)
  end

  defp select(_, selected, _, context),
    do: ToolCatalog.from_input(selected, Map.get(context, :jido_ai_tool_defaults, %{}))

  defp synchronize(options, [], true),
    do: options |> Keyword.drop([:tools, :tool_choice]) |> Keyword.put(:stream, false)

  defp synchronize(options, [], false), do: Keyword.drop(options, [:tools, :tool_choice])

  defp synchronize(options, catalog, false),
    do: Keyword.put(options, :tools, ToolCatalog.definitions(catalog))

  defp config(state, context) do
    defaults = Map.get(context, :jido_ai_tool_defaults, %{})

    config =
      Config.new(%{
        model: state.model,
        system_prompt: state.profile.instructions,
        max_iterations: state.profile.controls.max_iterations,
        streaming: state.profile.requests.streaming,
        output: state.output,
        request_transformer: state.profile.reasoning[:request_transformer],
        llm_opts: state.options,
        pending_input_server: context[:jido_ai_input_queue],
        tool_timeout_ms: defaults[:timeout] || 5_000,
        tool_max_retries: defaults[:max_retries] || 0,
        tool_retry_backoff_ms: defaults[:retry_backoff] || 0,
        tool_concurrency: state.profile.reasoning.tool_concurrency,
        effect_policy: Jido.AI.Runtime.ToolInterception.policy(state.profile),
        emit_telemetry?: Map.get(state.profile.observability, :emit_telemetry?, true),
        capture_deltas?: Map.get(state.profile.observability, :emit_llm_deltas?, true)
      })

    %{config | tools: Map.new(state.profile.tools, &{&1.name, &1.target})}
  end

  def state_view(state, context) do
    record = context[:jido_ai_request_record]
    conversation = Map.get(state, :repair_data, %{})[:conversation] || state.messages
    original = Map.get(state, :repair_data, %{})[:original] || state
    response = original[:response]
    events = Jido.AI.Orchestration.event_state(context)
    run_id = if record, do: record.run_id, else: state.run_id

    %State{
      run_id: run_id,
      request_id: if(record, do: record.id, else: state.request_id),
      context: State.conversation(Jido.AI.Model.Messages.entries(conversation.messages), nil),
      iteration: Jido.AI.Runtime.State.model_iteration(state),
      llm_call_id: original[:llm_call_id],
      llm_response_id: if(response, do: response.id),
      seq: Map.get(events, :seq, 0),
      status: if(state.repairs > 0, do: :completed, else: :running),
      result: Map.get(state, :repair_data, %{})[:raw],
      output: Map.get(state, :output_meta, %{}),
      usage: state.usage,
      pending_tool_calls:
        Enum.map(
          Map.get(state, :tool_meta, %{})[:tool_results] || [],
          &struct(Jido.AI.Reasoning.ReAct.PendingToolCall, &1)
        ),
      active_tools: Map.new(Map.get(original, :active_tools, []), &{&1.name, &1.target}),
      streaming_text:
        if(state.repairs > 0 && response && state.profile.requests.streaming,
          do: ReqLLM.Response.text(response),
          else: ""
        ),
      started_at_ms: state.started_at_ms,
      updated_at_ms: System.system_time(:millisecond)
    }
  end

  def latest_query(context) do
    {:ok, messages} = Jido.AI.Thread.Projection.messages(context)

    case Enum.find(Enum.reverse(messages), &(&1.role == :user)) do
      %{content: content} when is_binary(content) -> content
      %{content: content} when is_list(content) -> Jido.AI.Query.summarize(content)
      _ -> ""
    end
  end

  defp messages(context),
    do: Jido.AI.Model.Messages.entries(context.messages)
end
