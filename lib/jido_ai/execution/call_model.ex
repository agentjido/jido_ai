defmodule Jido.AI.Execution.CallModel do
  @moduledoc false
  use Jido.Action, name: "ai_call_model", schema: Jido.AI.Execution.State.schema()
  alias Jido.AI.Control
  alias Jido.AI.Profile
  alias Jido.AI.ToolCatalog
  alias Jido.AI.Usage

  @impl Jido.Action
  def run(params, context) do
    Jido.AI.Error.capture(fn ->
      position = Jido.AI.Execution.State.model_iteration(params)

      with :ok <- Jido.AI.Orchestration.reasoning_iteration(context, position),
           :ok <- Jido.AI.Orchestration.inspect_reasoning(context, Jido.AI.Reasoning.inspection(params)),
           do: execute(params, context)
    end)
  end

  defp execute(%{checkpoint_phase: :after_llm} = state, _),
    do: {:ok, Map.delete(state, :checkpoint_phase)}

  defp execute(%{checkpoint_phase: phase} = state, context)
       when phase in [:before_llm, :after_tools],
       do: execute(Map.delete(state, :checkpoint_phase), context)

  defp execute(state, context) do
    if state.profile.reasoning.method == :react && context[:jido_ai_iteration_limit_result] &&
         state.repairs == 0 &&
         state.iterations >= state.profile.controls.max_iterations do
      {:ok,
       Map.merge(state, %{
         limit_result: "Maximum iterations reached without a final answer.",
         termination_reason: :max_iterations
       })}
    else
      case call(state, context) do
        {:error, reason} -> Jido.AI.Execution.OutputState.fail(state, reason, context)
        result -> result
      end
    end
  end

  defp call(state, context) do
    remaining = state.deadline - System.monotonic_time(:millisecond)
    callback? = state.repairs > 0 && state.output.repair_fun != nil

    with true <- remaining > 0,
         true <- callback? or state.model_calls < state.profile.controls.max_model_calls,
         true <- state.repairs > 0 or state.iterations < state.profile.controls.max_iterations,
         {:ok, state} <- Jido.AI.Execution.PendingInput.drain(state, context),
         state = Map.put(state, :llm_call_id, Jido.Signal.ID.generate!()),
         request = request(state, remaining),
         {:ok, request, active_tools} <-
           Jido.AI.Execution.RequestTransform.prepare(state, request, context),
         :ok <- Control.check(state.profile, :model, request, context, state.deadline),
         remaining = state.deadline - System.monotonic_time(:millisecond),
         true <- remaining > 0,
         options = Keyword.update!(request.options, :receive_timeout, &min(&1, remaining)) do
      if callback?,
        do: repair_callback(state, %{request | options: options}, context),
        else: generate(state, %{request | options: options}, active_tools, context, remaining)
    else
      false -> Profile.error("controls", "AI request limit reached")
      error -> error
    end
  end

  defp generate(state, request, active_tools, context, remaining) do
    with :ok <-
           Jido.AI.Orchestration.emit(
             context,
             :llm_started,
             Map.merge(
               %{
                 model_call: state.model_calls + 1,
                 call_id: state.llm_call_id,
                 model: Jido.AI.Models.label(request.model)
               },
               Jido.AI.Reasoning.event(state)
             )
           ),
         {:model_result, {:ok, %{response: response}}} <-
           {:model_result,
            Jido.Exec.run(
              Jido.AI.Model.Generate,
              request,
              context
              |> Map.take([:jido_ai_events, :jido_ai_quota])
              |> Map.put(:jido_ai_quota_call_id, state.llm_call_id),
              timeout: remaining
            )},
         :ok <- Control.check(state.profile, :model, response, context, state.deadline),
         response =
           Jido.AI.Model.Messages.bind_response(response, Jido.AI.Orchestration.Transcript.request_refs(context)),
         :ok <- Jido.AI.Orchestration.account(context, response.usage),
         :ok <- terminal_response(response, request, state, context),
         {:ok, state} <-
           Jido.AI.Orchestration.Transcript.record(state, Jido.AI.Model.Messages.entries([response.message]), context),
         true <- System.monotonic_time(:millisecond) < state.deadline do
      event = Jido.AI.Observe.Event.model_response(response, state, request)
      :ok = Jido.AI.Orchestration.emit(context, :llm_completed, event)

      response_meta =
        Jido.AI.Request.Metadata.record_turn(Map.get(state, :response_meta, %{}), event)

      next =
        Map.merge(state, %{
          active_tools: active_tools,
          object_request: request.schema != nil,
          response: response,
          response_meta: response_meta,
          model_calls: state.model_calls + 1,
          iterations: state.iterations + if(state.repairs == 0, do: 1, else: 0),
          usage: Usage.merge(state.usage, response.usage)
        })

      Jido.AI.Execution.Checkpoint.pause(next, :after_llm, context)
    else
      {:model_result, {:error, reason}} when state.repairs > 0 ->
        {:ok,
         state
         |> Map.put(:repair_result, {:error, Jido.AI.Error.for_storage(reason)})
         |> Map.update!(:model_calls, &(&1 + 1))}

      {:model_result, {:error, reason}} ->
        {:error, reason}

      false ->
        Profile.error("controls", "AI request deadline reached")

      error ->
        error
    end
  end

  defp repair_callback(state, request, context) do
    data = state.repair_data
    record = context[:jido_ai_request_record]

    callback_context =
      Map.merge(context, %{
        model: request.model,
        messages: Map.get(request, :public_messages, request.messages.messages),
        llm_opts: Keyword.drop(request.options, [:tools, :tool_choice]),
        user_message: data.user_message,
        request_id: if(record, do: record.id, else: state.request_id),
        run_id: if(record, do: record.run_id, else: state.run_id)
      })

    result = Jido.AI.Output.repair(state.output, data.raw, data.reason, callback_context)
    {:ok, Map.put(state, :repair_result, result)}
  end

  defp terminal_response(response, request, state, context) do
    result =
      cond do
        response.finish_reason not in [nil, :stop, :tool_calls, "stop", "tool_calls", "completed"] ->
          {:error, {:incomplete_response, response.finish_reason}}

        request.schema == nil and response.finish_reason in [:tool_calls, "tool_calls"] and
            ReqLLM.Response.tool_calls(response) == [] ->
          # A provider can discard an incomplete or unnamed tool call during
          # assembly. An empty declared tool round is not a final answer.
          {:error, {:incomplete_response, :tool_calls}}

        true ->
          :ok
      end

    case result do
      {:error, reason} ->
        :ok = Jido.AI.Orchestration.failure_type(context, :llm_response)

        received =
          state
          |> Map.put(:response, response)
          |> Map.put(:usage, Usage.merge(state.usage, response.usage))

        {:error, Jido.AI.Reasoning.failure(received, reason)}

      other ->
        other
    end
  end

  defp request(state, remaining) do
    tools = Jido.AI.Reasoning.tools(state)

    options =
      state.options
      |> Keyword.put(
        :receive_timeout,
        min(remaining, Keyword.get(state.options, :receive_timeout, remaining))
      )

    options =
      if tools == [],
        do: Keyword.delete(options, :tools),
        else: Keyword.put(options, :tools, ToolCatalog.definitions(tools))

    options =
      if Jido.AI.Reasoning.tools_disabled?(state),
        do: Keyword.delete(options, :tool_choice),
        else: options

    # Tool-capable rounds request JSON by instruction. A repair has no tools and
    # uses the provider's object contract. Both paths use the same validator.
    schema =
      if tools == [],
        do: Jido.AI.Reasoning.provider_schema(state.profile, state.output),
        else: nil

    options =
      if state.repairs > 0,
        do: options |> Keyword.drop([:tools, :tool_choice]) |> Keyword.put(:stream, false),
        else: options

    request = %{
      model: state.model,
      messages: state.messages,
      options: options,
      schema: schema,
      stream: state.repairs == 0 and state.streaming
    }

    if state.repairs > 0,
      do: Map.put(request, :public_messages, state.repair_data.messages),
      else: request
  end
end
