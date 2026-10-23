defmodule Jido.AI.Actions.CompleteResponse do
  @moduledoc """
  Shapes the current model response into the common reasoning Flow result.

  The result contains the output, portable usage counters, and a sanitized
  trace. It does not include a ReqLLM response or private model reasoning.
  """

  alias Jido.AI.{Request, Result}
  alias Jido.AI.Reasoning.State

  use Jido.Action,
    name: "jido_ai_complete_response",
    description: "Complete one AI reasoning response"

  @impl Jido.Action
  def run(%{__jido_ai_reasoning__: true} = state, _context), do: result(state)

  @doc false
  @spec result(State.t()) :: {:ok, map()} | {:error, term()}
  def result(%{__jido_ai_reasoning__: true} = state) do
    private = State.private(state)

    with {:ok, output} <- Request.response_output(private.response, private.output_descriptor) do
      state =
        State.trace(state, :request_completed, %{
          output: State.summarize(output),
          usage: State.usage(state)
        })

      events = Enum.reverse(state.trace)
      {:ok, Result.completed(state, output, State.usage(state), events)}
    end
  end
end
