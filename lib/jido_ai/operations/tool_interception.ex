defmodule Jido.AI.Runtime.ToolInterception do
  @moduledoc false

  def policy(profile),
    do: Jido.AI.Effects.intersect_policies(profile.effect_policy, profile.reasoning.effect_policy)

  def context(state, context) do
    context
    |> Map.merge(identity(state, context))
    |> Map.put(:agent_state, state.effect_plan.state)
    |> Map.put(:state, state.effect_plan.state)
    |> Map.put(:effect_policy, policy(state.profile))
  end

  def identity(state, context) do
    record = context[:jido_ai_request_record]

    %{
      request_id: if(record, do: record.id, else: state.request_id),
      run_id: if(record, do: record.run_id, else: state.run_id),
      agent_id: context.jido_ai_agent.id,
      agent_module: context.jido_ai_agent.module
    }
  end

  def module(profile, context) do
    module = profile.tool_interceptor || context.jido_ai_agent.module

    if is_atom(module) and not is_nil(module) and Code.ensure_loaded?(module) and
         (function_exported?(module, :before_tool_call, 2) or
            function_exported?(module, :after_tool_call, 3)),
       do: module
  end

  def before(call, state, context) do
    case module(state.profile, context) do
      nil ->
        {:ok, call}

      module ->
        with {:ok, %{call: prepared}} <-
               invoke(:before, module, call, nil, context(state, context), state.deadline),
             do: {:ok, %{call | arguments: prepared.arguments}}
    end
  end

  def finish(call, raw, attempts, duration, context) do
    context =
      context
      |> Map.merge(call.runtime_identity)
      |> Map.put(:agent_state, call.agent_state)
      |> Map.put(:state, call.agent_state)
      |> Map.put(:effect_policy, call.effect_policy)

    outcome =
      if call.interceptor do
        invoke(:after, call.interceptor, call, raw, context, call.deadline)
      else
        {result, stats} = Jido.AI.Effects.filter_result(raw, call.effect_policy)
        {:ok, %{result: result, stats: stats}}
      end

    with {:ok, %{result: result, stats: stats}} <- outcome do
      refs = Jido.AI.Skill.Runtime.refs(call, raw, result)

      completed =
        Jido.AI.ToolResult.completed(call, result, attempts, duration)
        |> Map.put(:effects, Map.take(stats, [:received_count, :allowed_count, :dropped_count]))

      :ok =
        Jido.AI.Session.emit(context, :tool_completed, %{
          tool_call_id: call.id,
          tool_name: call.name,
          result: result,
          attempts: attempts,
          duration_ms: duration,
          completed: completed,
          refs: refs
        })

      {:ok,
       %{
         id: call.id,
         name: call.name,
         agent_state: call.agent_state,
         result: result,
         completed: completed,
         refs: refs,
         content: Jido.AI.ToolResult.content(result)
       }}
    end
  end

  def finish_all(%{tool_results: [%{call: _} | _] = pending} = state, context) do
    Enum.reduce_while(pending, {:ok, %{state | tool_results: []}}, fn entry, {:ok, state} ->
      with {:ok, result} <- finish(entry.call, entry.raw, entry.attempts, entry.duration, context),
           {:ok, state} <- Jido.AI.Runtime.Continue.apply_results(state, [result], context) do
        {:cont, {:ok, state}}
      else
        error -> {:halt, error}
      end
    end)
  end

  def finish_all(state, _), do: {:ok, state}

  defp invoke(stage, module, call, result, context, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0 do
      Jido.Exec.run(
        Jido.AI.Runtime.ToolHook,
        %{
          stage: stage,
          module: module,
          call: %{
            id: call.id,
            name: call.name,
            arguments: call.arguments,
            action_module: call.tool.target
          },
          result: result
        },
        context,
        timeout: remaining
      )
    else
      Jido.AI.Profile.error("controls", "AI request deadline reached")
    end
  end
end

defmodule Jido.AI.Runtime.ToolHook do
  @moduledoc false
  use Jido.Action, name: "ai_tool_hook"
  def run(params, context), do: Jido.AI.Error.capture(fn -> execute(params, context) end)

  defp execute(%{stage: :before, module: module, call: call}, context) do
    case Jido.AI.ToolInterceptor.before_tool_call(module, call, context) do
      {:ok, call} -> {:ok, %{call: call}}
      {:interrupt, value} -> {:error, {:interrupt, value}}
      error -> error
    end
  end

  defp execute(%{stage: :after, module: module, call: call, result: result}, context) do
    with {:ok, result, stats} <-
           Jido.AI.ToolInterceptor.after_tool_call_with_stats(module, call, result, context),
         do: {:ok, %{result: result, stats: stats}}
  end
end
