defmodule Jido.AI.Actions.CallModel do
  @moduledoc """
  Runs one bounded model call for a reasoning Flow.

  The Action accepts the portable `Jido.AI.Reasoning.State` map and returns an
  updated state. It does not execute tools or select the next reasoning step.
  """

  alias Jido.AI.Deadline
  alias Jido.AI.Reasoning.State

  use Jido.Action,
    name: "jido_ai_call_model",
    description: "Run one bounded AI model call"

  @impl Jido.Action
  def run(%{__jido_ai_reasoning__: true} = state, _context) do
    private = State.private(state)
    started_at = System.monotonic_time(:millisecond)

    with :ok <- model_call_allowed(state),
         {:ok, options} <- request_options(private),
         {:ok, response} <- ReqLLM.generate_text(private.model, private.conversation, options) do
      call = state.model_calls + 1
      duration_ms = System.monotonic_time(:millisecond) - started_at
      tool_calls = ReqLLM.Response.tool_calls(response)
      call_metadata = ReqLLM.Response.call_metadata(response)

      event =
        call_metadata
        |> Map.take([
          :response_id,
          :request_id,
          :model,
          :finish_reason,
          :attempts,
          :timings,
          :warnings
        ])
        |> Map.merge(%{
          type: :model_completed,
          call: call,
          duration_ms: duration_ms,
          tool_calls: Enum.map(tool_calls, &tool_trace/1),
          usage: State.normalize_usage(response.usage)
        })

      state =
        state
        |> State.put_private(%{private | response: response})
        |> State.add_usage(response.usage)
        |> Map.put(:model_calls, call)
        |> State.trace(event)

      {:ok, state}
    end
  end

  defp tool_trace(call), do: %{id: call.id, name: ReqLLM.ToolCall.name(call)}

  defp model_call_allowed(state) do
    if state.model_calls < state.controls.max_model_calls,
      do: :ok,
      else: {:error, {:limit_exceeded, :max_model_calls}}
  end

  defp request_options(private) do
    configured_timeout =
      case Keyword.get(private.request_options, :receive_timeout) do
        timeout when is_integer(timeout) and timeout > 0 -> timeout
        _other -> private.deadline.timeout
      end

    with {:ok, timeout} <- Deadline.cap(private.deadline, configured_timeout) do
      {:ok, Keyword.put(private.request_options, :receive_timeout, timeout)}
    end
  end
end
