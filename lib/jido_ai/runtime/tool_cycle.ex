defmodule Jido.AI.Runtime.ToolCycle do
  @moduledoc false
  alias Jido.AI.Orchestration

  @warning "You already called the same tool(s) with identical parameters in the previous iteration. Do NOT repeat the same calls. Either use the results you already have to form a final answer, or try a different approach."

  # Compare the full model arguments, before tool callbacks. IDs and order do
  # not affect this check. A warning never skips the actual tool executions.
  def record(state, context) do
    signature =
      state.response
      |> ReqLLM.Response.tool_calls()
      |> Enum.map(fn call ->
        call = ReqLLM.ToolCall.to_map(call)
        {call.name, call.arguments}
      end)
      |> Enum.sort()
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    meta = Map.get(state, :tool_meta, %{})
    repeated? = meta[:prev_tool_signature] == signature
    state = Map.put(state, :tool_meta, Map.put(meta, :prev_tool_signature, signature))

    with :ok <- Orchestration.tool_signature(context, signature) do
      if repeated? do
        message = ReqLLM.Context.user(@warning)

        Jido.AI.Orchestration.Transcript.record(
          %{state | messages: ReqLLM.Context.append(state.messages, message)},
          Jido.AI.Orchestration.Transcript.query(@warning, %{}),
          context
        )
      else
        {:ok, state}
      end
    end
  end
end
