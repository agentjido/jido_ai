defmodule Jido.AI.Flow.ReAct.ContinueTools do
  @moduledoc false

  alias Jido.AI.Reasoning.State

  use Jido.Action,
    name: "jido_ai_react_continue_tools",
    description: "Append one successful tool round"

  @impl Jido.Action
  def run(%{state: %{__jido_ai_reasoning__: true} = state, results: results}, _context)
      when is_list(results) do
    private = State.private(state)
    calls = ReqLLM.Response.tool_calls(private.response)

    if length(calls) == length(results) do
      messages =
        Enum.zip_with(calls, results, fn call, result ->
          ReqLLM.Context.tool_result_message(
            ReqLLM.ToolCall.name(call),
            call.id,
            result
          )
        end)

      with {:ok, conversation} <-
             ReqLLM.Context.append_tool_exchange(
               private.response.context,
               private.response,
               messages
             ) do
        call_count = length(calls)
        iteration = state.iterations + 1

        state =
          state
          |> State.put_private(%{private | conversation: conversation, response: nil})
          |> Map.put(:tool_calls, state.tool_calls + call_count)
          |> Map.put(:iterations, iteration)
          |> State.trace(:tool_round_completed, %{
            iteration: iteration,
            duration_ms: State.since_last_event_ms(state),
            calls:
              Enum.zip_with(calls, results, fn call, result ->
                tool_trace(call, result, private.tool_specs)
              end)
          })

        {:ok, %{request: state}}
      end
    else
      {:error, :tool_result_count_mismatch}
    end
  end

  defp tool_trace(call, result, specs) do
    name = ReqLLM.ToolCall.name(call)
    spec = Enum.find(specs, &(&1.name == name))

    %{
      id: call.id,
      name: name,
      kind: if(spec, do: spec.kind, else: :unknown),
      status: :ok,
      output: State.summarize(result)
    }
  end
end
