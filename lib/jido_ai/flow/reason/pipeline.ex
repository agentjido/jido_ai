defmodule Jido.AI.Flow.Reason.Pipeline do
  @moduledoc false

  alias Jido.AI.Reasoning.State
  alias Jido.Flow.Ref

  @spec new(State.t()) :: {:ok, Jido.Flow.t()} | {:error, Exception.t()}
  def new(%{__jido_ai_reasoning__: true} = state) do
    {input_control, previous} = control(state.controls.input, :input, nil)

    reason = %{
      kind: :subflow,
      name: "reason",
      flow: state.reasoning,
      params: Ref.input([]),
      needs: List.wrap(previous)
    }

    {output_control, previous} = control(state.controls.output, :output, "reason")

    finish = %{
      kind: :step,
      name: "finish",
      action: Jido.AI.Flow.Reason.Return,
      params: %{request: Ref.input(:request), result: Ref.result("reason")},
      needs: [previous]
    }

    Jido.Flow.new(%{
      name: "jido_ai_reason_pipeline",
      description: "Run AI controls around one selected reasoning Flow",
      components: input_control ++ [reason] ++ output_control ++ [finish],
      output: Ref.result("finish")
    })
  end

  defp control(nil, _stage, previous), do: {[], previous}

  defp control(action, stage, previous) do
    name = "#{stage}_control"

    value =
      case stage do
        :input -> Ref.input([:request, :input])
        :output -> Ref.result("reason", :output)
      end

    component = %{
      kind: :step,
      name: name,
      action: action,
      params: %{stage => value},
      needs: List.wrap(previous)
    }

    {[component], name}
  end
end
