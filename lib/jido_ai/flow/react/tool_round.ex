defmodule Jido.AI.Flow.ReAct.ToolRound do
  @moduledoc false

  alias Jido.Flow.Ref

  @spec tools([map()]) :: {:ok, Jido.Flow.t()} | {:error, Exception.t()}
  def tools(calls) when is_list(calls) and calls != [] do
    components =
      calls
      |> Enum.with_index(1)
      |> Enum.map(fn {%{params: params, spec: spec}, index} ->
        tool_component("tool_#{index}", spec, params)
      end)

    names = Enum.map(components, & &1.name)

    continue = %{
      kind: :step,
      name: "continue",
      action: Jido.AI.Flow.ReAct.ContinueTools,
      params: %{
        state: Ref.input(:state),
        results: Enum.map(names, &Ref.result/1)
      },
      needs: names
    }

    build(components ++ [continue])
  end

  @spec rejected() :: {:ok, Jido.Flow.t()} | {:error, Exception.t()}
  def rejected do
    continue = %{
      kind: :step,
      name: "continue",
      action: Jido.AI.Flow.ReAct.ContinueRejectedTools,
      params: %{
        state: Ref.input(:state),
        resolutions: Ref.input(:resolutions)
      }
    }

    build([continue])
  end

  defp build(components) do
    reason = %{
      kind: :subflow,
      name: "reason",
      flow: Jido.AI.Flow.ReAct,
      params: Ref.result("continue"),
      needs: ["continue"]
    }

    Jido.Flow.new(%{
      name: "jido_ai_react_tool_round",
      description: "Run one tool round and continue ReAct",
      components: components ++ [reason],
      output: Ref.result("reason")
    })
  end

  defp tool_component(name, %{kind: :action, target: target}, params) do
    %{kind: :step, name: name, action: target, params: params}
  end

  defp tool_component(name, %{kind: :flow, target: target}, params) do
    %{kind: :subflow, name: name, flow: target, params: params}
  end
end
