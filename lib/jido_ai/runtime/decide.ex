defmodule Jido.AI.Runtime.Decide do
  @moduledoc false
  use Jido.Action, name: "ai_decide", schema: Jido.AI.Runtime.State.schema()
  alias Jido.AI.{Control, Output, Profile, ToolCatalog}

  @impl Jido.Action
  def run(params, context), do: Jido.AI.Error.capture(fn -> execute(params, context) end)

  defp execute(%{repair_result: {:ok, answer}} = state, context),
    do: finish_output(Map.delete(state, :repair_result), context, answer)

  defp execute(%{repair_result: {:error, reason}} = state, context),
    do: repair(Map.delete(state, :repair_result), reason, context)

  defp execute(%{limit_result: text} = state, context) do
    with :ok <- Jido.AI.Runtime.PendingInput.seal(context),
         do: finish_output(state, context, text)
  end

  defp execute(state, context) do
    calls = ReqLLM.Response.tool_calls(state.response)

    cond do
      calls == [] or Map.get(state, :object_request, false) ->
        case Jido.AI.Reasoning.advance(state) do
          {:continue, next} ->
            {:continue, next, Jido.AI.Runtime.ReasonFlow}

          {:done, next} ->
            with :ok <- Jido.AI.Orchestration.inspect_reasoning(context, Jido.AI.Reasoning.inspection(next)),
                 do: finish(next, context)

          {:error, reason} ->
            Jido.AI.Runtime.OutputState.fail(state, reason, context)
        end

      Jido.AI.Reasoning.single_pass?(state.profile.reasoning.method) ->
        Jido.AI.Runtime.OutputState.fail(
          state,
          {:unexpected_tool_calls, state.profile.reasoning.method},
          context
        )

      true ->
        tools(state, calls, context)
    end
  end

  defp tools(state, calls, context) do
    with true <- state.repairs == 0,
         {:ok, state} <- Jido.AI.Reasoning.tool_round(state),
         true <- state.tool_calls + length(calls) <= state.profile.controls.max_tool_calls,
         {:ok, batch} <-
           ToolCatalog.admit(
             Map.get(state, :active_tools, state.profile.tools),
             calls,
             &Jido.AI.Runtime.ToolInterception.before(&1, state, context)
           ),
         :ok <-
           Jido.AI.Runtime.Preflight.check(
             state.profile,
             batch,
             Jido.AI.Runtime.ToolInterception.context(state, context),
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
            interceptor: Jido.AI.Runtime.ToolInterception.module(state.profile, context),
            runtime_identity: Jido.AI.Runtime.ToolInterception.identity(state, context),
            effect_policy: Jido.AI.Runtime.ToolInterception.policy(state.profile)
          })
        end)

      [first | pending] = Enum.chunk_every(batch, state.profile.reasoning.tool_concurrency)

      {:continue,
       Map.merge(state, %{
         batch: first,
         pending_batches: pending,
         tool_results: [],
         tool_calls: state.tool_calls + length(batch)
       }), Jido.AI.Runtime.ToolsFlow}
    else
      false ->
        {:error, reason} = Profile.error("controls", "AI tool limit reached")
        {:error, Jido.AI.Reasoning.failure(state, reason)}

      {:error, reason} ->
        {:error, Jido.AI.Reasoning.failure(state, reason)}
    end
  end

  defp finish(state, context) do
    case Jido.AI.Runtime.PendingInput.seal_if_empty(context) do
      :sealed ->
        finish_output(state, context)

      :pending ->
        with {:ok, state} <-
               Jido.AI.Runtime.PendingInput.drain(
                 %{state | messages: state.response.context},
                 context
               ),
             do: {:continue, state, Jido.AI.Runtime.ReasonFlow}

      {:error, reason} ->
        {:error, {:pending_input_server, reason}}
    end
  end

  defp finish_output(state, context) do
    finish_output(state, context, state.response)
  end

  defp finish_output(state, context, value) do
    state = Jido.AI.Runtime.OutputState.start(state, value, context)

    case Jido.AI.Reasoning.parse(state, value) do
      {:ok, answer, method_meta} ->
        state = Jido.AI.Runtime.OutputState.validated(state, answer, context)

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
              Jido.AI.Runtime.State.iteration(state, :terminal)
            )

          meta = if state.output, do: Map.put(meta, :output, state.output_meta), else: meta

          with {:ok, meta} <- Jido.AI.Runtime.Checkpoint.terminal(state, meta, context) do
            content = Jido.AI.Runtime.OutputState.content(value)

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
            Jido.AI.Runtime.OutputState.fail(state, reason, context)

          {:error, reason} ->
            Jido.AI.Runtime.OutputState.fail(state, reason, context)
        end

      {:method_error, reason} ->
        Jido.AI.Runtime.OutputState.fail(state, reason, context)

      {:error, reason} ->
        repair(state, reason, context)
    end
  end

  defp repair(state, reason, context) do
    if state.output.on_validation_error == :repair &&
         state.repairs < state.profile.result.max_repairs do
      state = Jido.AI.Runtime.OutputState.repair(state, reason, context)
      raw = state.output_raw

      view = Jido.AI.Runtime.RequestTransform.state_view(state, context)

      user_message =
        Map.get(state, :repair_data, %{})[:user_message] ||
          Jido.AI.Runtime.RequestTransform.latest_query(view.context)

      conversation =
        Map.get(state, :repair_data, %{})[:conversation] ||
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
          conversation: conversation,
          original: original
        })

      {:continue, next, Jido.AI.Runtime.ReasonFlow}
    else
      Jido.AI.Runtime.OutputState.fail(state, reason, context)
    end
  end
end
