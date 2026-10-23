defmodule Jido.AI.Flow.ReAct.ContinueRejectedTools do
  @moduledoc false

  alias Jido.AI.ToolAdapter
  alias Jido.AI.Reasoning.State

  use Jido.Action,
    name: "jido_ai_react_continue_rejected_tools",
    description: "Append one rejected tool round"

  @impl Jido.Action
  def run(
        %{
          state: %{__jido_ai_reasoning__: true} = state,
          resolutions: encoded_resolutions
        },
        _context
      )
      when is_binary(encoded_resolutions) do
    private = State.private(state)
    resolutions = :erlang.binary_to_term(encoded_resolutions, [:safe])
    messages = ToolAdapter.rejection_messages(resolutions)

    with {:ok, conversation} <-
           ReqLLM.Context.append_tool_exchange(
             private.response.context,
             private.response,
             messages
           ) do
      call_count = length(resolutions)
      iteration = state.iterations + 1

      state =
        state
        |> State.put_private(%{private | conversation: conversation, response: nil})
        |> Map.put(:tool_calls, state.tool_calls + call_count)
        |> Map.put(:iterations, iteration)
        |> State.trace(%{
          type: :tool_round_completed,
          iteration: iteration,
          duration_ms: State.since_last_event_ms(state),
          calls: Enum.map(resolutions, &tool_trace(&1, private.tool_specs))
        })

      {:ok, %{request: state}}
    end
  end

  defp tool_trace(resolution, specs) do
    spec = Enum.find(specs, &(&1.name == resolution.name))

    %{
      id: resolution.id,
      name: resolution.name,
      kind: if(spec, do: spec.kind, else: :unknown),
      status: resolution.state
    }
  end
end
