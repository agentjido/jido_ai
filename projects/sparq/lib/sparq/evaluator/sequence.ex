defmodule Sparq.Evaluator.Sequence do
  alias Sparq.Context

  @doc """
  Evaluates a sequence of expressions in order.
  Returns {last_value, updated_context}.
  """
  def evaluate_sequence([], context), do: {nil, context}

  def evaluate_sequence([expr], context) do
    case Sparq.Evaluator.evaluate(expr, context) do
      {value, new_ctx} -> {value, new_ctx}
      error -> error
    end
  end

  def evaluate_sequence([expr | rest], context) do
    case Sparq.Evaluator.evaluate(expr, context) do
      {_value, new_ctx} -> evaluate_sequence(rest, new_ctx)
      error -> error
    end
  end

  @doc """
  Helper to pop a frame after sequence evaluation.
  """
  def pop_frame({value, context}), do: {value, Context.pop_frame(context)}
  def pop_frame({:error, _, _} = error), do: error
end
