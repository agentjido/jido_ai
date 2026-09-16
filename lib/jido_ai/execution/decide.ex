defmodule Jido.AI.Execution.Decide do
  @moduledoc false
  use Jido.Action, name: "ai_decide", schema: Jido.AI.Execution.State.schema()
  alias Jido.AI.Control
  alias Jido.AI.Output
  alias Jido.AI.Profile
  alias Jido.AI.ToolCatalog

  @impl Jido.Action
  def run(params, context), do: Jido.AI.Error.capture(fn -> execute(params, context) end)

  defp execute(%{repair_result: {:ok, answer}} = state, context),
    do: finish_output(Map.delete(state, :repair_result), context, answer)

  defp execute(%{repair_result: {:error, reason}} = state, context),
    do: repair(Map.delete(state, :repair_result), reason, context)

  defp execute(%{limit_result: text} = state, context) do
    with :ok <- Jido.AI.Execution.PendingInput.seal(context),
         do: finish_output(state, context, text)
  end

  defp execute(state, context) do
    calls = ReqLLM.Response.tool_calls(state.response)

    cond do
      calls == [] or Map.get(state, :object_request, false) ->
        case Jido.AI.Reasoning.advance(state) do
          {:continue, next} ->
            {:continue, next, Jido.AI.Execution.ModelFlow}

          {:done, next} ->
            with :ok <- Jido.AI.Orchestration.inspect_reasoning(context, Jido.AI.Reasoning.inspection(next)),
                 do: finish(next, context)

          {:error, reason} ->
            Jido.AI.Execution.OutputState.fail(state, reason, context)
        end

      Jido.AI.Reasoning.single_pass?(state.profile.reasoning.method) ->
        Jido.AI.Execution.OutputState.fail(
          state,
          {:unexpected_tool_calls, state.profile.reasoning.method},
          context
        )

      true ->
        tools(state, calls, context)
    end
  end

  defp tools(state, calls, context) do
    catalog = Map.get(state, :active_tools, state.profile.tools)
    normalized = Enum.map(calls, &ReqLLM.ToolCall.to_map/1)

    if Enum.any?(normalized, fn call -> not Enum.any?(catalog, &(&1.name == call.name)) end) do
      reject_unknown_batch(state, calls, catalog, context)
    else
      execute_tools(state, calls, context)
    end
  end

  # An unknown tool is recoverable model input, not permission to execute a
  # fallback. Reject the whole batch before effects and let the model correct it.
  defp reject_unknown_batch(state, calls, catalog, context) do
    known =
      Enum.filter(calls, fn call ->
        name = ReqLLM.ToolCall.to_map(call).name
        Enum.any?(catalog, &(&1.name == name))
      end)

    calls = Enum.map(calls, &ReqLLM.ToolCall.to_map/1)
    ids = Enum.map(calls, & &1.id)

    with true <- state.repairs == 0 and state.tool_calls + length(calls) <= state.profile.controls.max_tool_calls,
         true <- Enum.all?(calls, &(is_binary(&1.id) and &1.id != "" and is_map(&1.arguments))),
         true <- length(ids) == length(Enum.uniq(ids)),
         {:ok, _} <- ToolCatalog.admit(catalog, known),
         {:ok, state} <- Jido.AI.Reasoning.tool_round(state) do
      results =
        Enum.map(calls, fn call ->
          reason =
            if Enum.any?(catalog, &(&1.name == call.name)),
              do: "Batch rejected: another tool is unknown",
              else: "Unknown tool: #{call.name}"

          ReqLLM.Context.tool_result(call.id, call.name, Jason.encode!(%{ok: false, error: reason}))
        end)

      with {:ok, messages} <- ReqLLM.Context.append_tool_exchange(state.response.context, state.response, results),
           {:ok, state} <-
             Jido.AI.Orchestration.Transcript.record(state, Jido.AI.Model.Messages.entries(results), context) do
        {:continue, %{state | messages: messages, tool_calls: state.tool_calls + length(calls)},
         Jido.AI.Execution.ModelFlow}
      end
    else
      false ->
        {:error, reason} = Profile.error("tools.batch", "Invalid tool batch or exhausted tool limit")
        {:error, Jido.AI.Reasoning.failure(state, reason)}

      {:error, reason} ->
        {:error, Jido.AI.Reasoning.failure(state, reason)}
    end
  end

  defp execute_tools(state, calls, context) do
    with true <- state.repairs == 0,
         {:ok, state} <- Jido.AI.Reasoning.tool_round(state),
         true <- state.tool_calls + length(calls) <= state.profile.controls.max_tool_calls,
         {:ok, batch} <-
           ToolCatalog.admit(
             Map.get(state, :active_tools, state.profile.tools),
             calls,
             &Jido.AI.Execution.ToolInterception.before(&1, state, context)
           ),
         :ok <-
           Jido.AI.Execution.Preflight.check(
             state.profile,
             batch,
             Jido.AI.Execution.ToolInterception.context(state, context),
             state.deadline
           ),
         true <- System.monotonic_time(:millisecond) < state.deadline do
      batch =
        Enum.with_index(batch, state.tool_calls)
        |> Enum.map(fn {call, index} ->
          Map.merge(call, %{
            deadline: state.deadline,
            position: index,
            agent_state: state.effect_plan.state,
            profile: state.profile,
            interceptor: Jido.AI.Execution.ToolInterception.module(state.profile, context),
            runtime_identity: Jido.AI.Execution.ToolInterception.identity(state, context),
            effect_policy: Jido.AI.Execution.ToolInterception.policy(state.profile)
          })
        end)

      [first | pending] = Enum.chunk_every(batch, state.profile.reasoning.tool_concurrency)

      {:continue,
       Map.merge(state, %{
         batch: first,
         pending_batches: pending,
         tool_results: [],
         tool_calls: state.tool_calls + length(batch)
       }), Jido.AI.Execution.ToolsFlow}
    else
      false ->
        {:error, reason} = Profile.error("controls", "AI tool limit reached")
        {:error, Jido.AI.Reasoning.failure(state, reason)}

      {:error, reason} ->
        {:error, Jido.AI.Reasoning.failure(state, reason)}
    end
  end

  defp finish(state, context) do
    case Jido.AI.Execution.PendingInput.seal_if_empty(context) do
      :sealed ->
        finish_output(state, context)

      :pending ->
        with {:ok, state} <-
               Jido.AI.Execution.PendingInput.drain(
                 %{state | messages: state.response.context},
                 context
               ),
             do: {:continue, state, Jido.AI.Execution.ModelFlow}

      {:error, reason} ->
        {:error, {:pending_input_server, reason}}
    end
  end

  defp finish_output(state, context) do
    finish_output(state, context, state.response)
  end

  defp finish_output(state, context, value) do
    state = Jido.AI.Execution.OutputState.start(state, value, context)

    case Jido.AI.Reasoning.parse(state, value) do
      {:ok, answer, method_meta} ->
        state = Jido.AI.Execution.OutputState.validated(state, answer, context)

        with :ok <- Control.check(state.profile, :output, answer, context, state.deadline),
             true <- System.monotonic_time(:millisecond) < state.deadline do
          meta =
            Map.merge(
              Map.get(state, :response_meta, %{}),
              Map.take(state, [:usage, :model_calls, :tool_calls, :termination_reason])
            )
            |> Map.merge(Map.get(state, :tool_meta, %{}))
            |> Map.merge(method_meta)
            |> Map.put_new(:termination_reason, :final_answer)
            |> Map.put(
              :reasoning_iteration,
              Jido.AI.Execution.State.iteration(state, :terminal)
            )

          meta = if state.output, do: Map.put(meta, :output, state.output_meta), else: meta

          with {:ok, meta} <- Jido.AI.Execution.Checkpoint.terminal(state, meta, context) do
            content = Jido.AI.Execution.OutputState.content(value)

            {:ok,
             %{
               result: answer,
               content: content,
               value: if(state.output, do: answer, else: nil),
               meta: meta,
               effect_plan: state.effect_plan,
               history_delta: state.history_delta
             }}
          end
        else
          false ->
            {:error, reason} = Profile.error("controls", "AI request deadline reached")
            Jido.AI.Execution.OutputState.fail(state, reason, context)

          {:error, reason} ->
            Jido.AI.Execution.OutputState.fail(state, reason, context)
        end

      {:method_error, reason} ->
        Jido.AI.Execution.OutputState.fail(state, reason, context)

      {:error, reason} ->
        repair(state, reason, context)
    end
  end

  defp repair(state, reason, context) do
    if state.output.on_validation_error == :repair &&
         state.repairs < state.profile.result.max_repairs do
      state = Jido.AI.Execution.OutputState.repair(state, reason, context)
      raw = state.output_raw

      view = Jido.AI.Execution.RequestTransform.state_view(state, context)

      user_message =
        Map.get(state, :repair_data, %{})[:user_message] ||
          Jido.AI.Execution.RequestTransform.latest_query(view.context)

      conversation =
        Map.get(state, :repair_data, %{})[:context] ||
          if(Map.has_key?(state, :limit_result), do: state.messages, else: state.response.context)

      original =
        Map.get(state, :repair_data, %{})[:original] ||
          Map.take(state, [:llm_call_id, :response, :active_tools])

      request =
        Output.repair_request(raw, reason, %{
          model: state.model,
          llm_opts: state.options,
          user_message: user_message
        })

      {:ok, messages} = ReqLLM.Context.normalize(request.messages)

      next =
        state
        |> Map.delete(:limit_result)
        |> Map.put(:messages, messages)
        |> Map.put(:repairs, state.repairs + 1)
        |> Map.put(:repair_data, %{
          raw: raw,
          reason: reason,
          user_message: user_message,
          messages: request.messages,
          context: conversation,
          original: original
        })

      {:continue, next, Jido.AI.Execution.ModelFlow}
    else
      Jido.AI.Execution.OutputState.fail(state, reason, context)
    end
  end
end
