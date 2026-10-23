defmodule Jido.AI.Flow.ReAct.Route do
  @moduledoc false

  alias Jido.AI.Actions.CompleteResponse
  alias Jido.AI.ToolAdapter
  alias Jido.AI.Flow.ReAct.ToolRound
  alias Jido.AI.Reasoning.State

  use Jido.Action,
    name: "jido_ai_react_route",
    description: "Select the ReAct result or next tool round"

  @impl Jido.Action
  def run(%{__jido_ai_reasoning__: true} = state, _context) do
    with {:ok, calls} <- actionable_tool_calls(state) do
      case calls do
        [] -> finish(state)
        calls -> continue(state, calls)
      end
    end
  end

  defp finish(state) do
    CompleteResponse.result(state)
  end

  defp continue(state, calls) do
    private = State.private(state)

    with :ok <- tool_calls_allowed(state, length(calls)),
         resolutions = Enum.map(calls, &ReqLLM.ToolCall.resolve(&1, private.tools)),
         {:ok, flow, input} <- next_tool_round(state, private, resolutions) do
      {:continue, input, flow}
    end
  end

  defp next_tool_round(state, private, resolutions) do
    if Enum.all?(resolutions, &(&1.state == :valid)) do
      with {:ok, calls} <- attach_specs(resolutions, private.tool_specs),
           {:ok, flow} <- ToolRound.tools(calls) do
        {:ok, flow, %{state: state}}
      end
    else
      with {:ok, flow} <- ToolRound.rejected() do
        {:ok, flow, %{state: state, resolutions: :erlang.term_to_binary(resolutions, [:deterministic])}}
      end
    end
  end

  defp attach_specs(resolutions, specs) do
    Enum.reduce_while(resolutions, {:ok, []}, fn resolution, {:ok, calls} ->
      case Enum.find(specs, &(&1.name == resolution.name)) do
        nil ->
          {:halt, {:error, {:unknown_tool, resolution.name}}}

        spec ->
          case ToolAdapter.decode_params(spec.target.schema(), resolution.validated_arguments) do
            {:ok, params} ->
              {:cont, {:ok, [%{params: params, resolution: resolution, spec: spec} | calls]}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
      end
    end)
    |> case do
      {:ok, calls} -> {:ok, Enum.reverse(calls)}
      error -> error
    end
  end

  defp actionable_tool_calls(%{__jido_ai_reasoning__: true} = state) do
    private = State.private(state)

    case private.response do
      %ReqLLM.Response{} = response -> actionable_tool_calls(response, private.output_descriptor)
      _other -> {:ok, []}
    end
  end

  defp actionable_tool_calls(response, output_descriptor) do
    calls = ReqLLM.Response.tool_calls(response)

    if match?(%ReqLLM.Output{}, output_descriptor) do
      {output_calls, tool_calls} =
        Enum.split_with(calls, &ReqLLM.ToolCall.matches_name?(&1, "structured_output"))

      case {output_calls, tool_calls} do
        {[], calls} ->
          {:ok, calls}

        {[_output_call], []} ->
          {:ok, []}

        {_output_calls, _tool_calls} ->
          {:error, {:invalid_model_response, :mixed_structured_output_and_tool_calls}}
      end
    else
      {:ok, calls}
    end
  end

  defp tool_calls_allowed(state, call_count) do
    cond do
      state.iterations >= state.controls.max_iterations ->
        {:error, {:limit_exceeded, :max_iterations}}

      state.tool_calls + call_count > state.controls.max_tool_calls ->
        {:error, {:limit_exceeded, :max_tool_calls}}

      true ->
        :ok
    end
  end
end
