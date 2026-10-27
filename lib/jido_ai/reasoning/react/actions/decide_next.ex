defmodule Jido.AI.Reasoning.ReAct.Actions.DecideNext do
  @moduledoc "Routes a model outcome to completion, repair, fallback, or tools."

  alias Jido.AI.Budget

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/decide-next",
    vsn: 1,
    name: "jido_ai_react_decide_next",
    description: "Choose the next graph after a model call",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: %{model_outcome: %{status: :budget}} = turn}, _context) do
    {:ok, complete(turn, blocked(turn, :limits, "maximum model calls reached"))}
  end

  def run(%{turn: %{model_outcome: %{status: :error}} = turn}, _context) do
    {:ok, recover_or_fail(turn, :model, turn.model_outcome.reason)}
  end

  def run(%{turn: %{output_allowed: false} = turn}, _context) do
    instruction = "Repair the previous response. #{turn.output_reason}. Return a valid final answer."
    {:ok, recover_or_block(turn, instruction)}
  end

  def run(%{turn: %{model_outcome: %{kind: :tool_calls}} = turn}, _context)
      when turn.tool_rounds >= turn.max_tool_rounds do
    {:ok, complete(turn, blocked(turn, :limits, "maximum tool rounds reached"))}
  end

  def run(%{turn: %{model_outcome: %{kind: :tool_calls, tool_calls: calls}} = turn}, _context)
      when turn.tool_call_count + length(calls) > turn.max_tool_calls do
    {:ok, complete(turn, blocked(turn, :limits, "maximum tool calls reached"))}
  end

  def run(%{turn: %{model_outcome: %{kind: :tool_calls}} = turn}, _context) do
    case Budget.resources(turn) do
      :ok ->
        kind = if review_required?(turn), do: :review, else: :tools
        {:ok, %{kind: kind, input: %{turn: %{turn | repair_instruction: nil}}}}

      {:error, _budget, reason} ->
        {:ok, complete(turn, blocked(turn, :limits, reason))}
    end
  end

  def run(%{turn: %{model_outcome: %{kind: :final_answer}} = turn}, _context) do
    result = %{
      status: :completed,
      output: turn.model_outcome.text,
      model_calls: turn.model_calls,
      tool_rounds: turn.tool_rounds,
      tool_calls: turn.tool_call_count,
      tool_errors: turn.tool_error_count,
      retries: turn.retries,
      guardrail: :none,
      reason: ""
    }

    {:ok, complete(turn, result)}
  end

  defp recover_or_fail(turn, guardrail, reason) do
    case Budget.before_model(turn) do
      {:error, _budget, budget_reason} ->
        complete(turn, blocked(turn, :limits, budget_reason))

      :ok ->
        cond do
          turn.model_outcome.retryable and turn.model_attempt <= turn.max_retries ->
            %{kind: :model, input: %{turn: Map.update!(turn, :retries, &(&1 + 1))}}

          turn.model_outcome.retryable and turn.model_index + 1 < length(turn.models) ->
            next = %{
              turn
              | model_index: turn.model_index + 1,
                model_attempt: 0,
                retries: turn.retries + 1
            }

            %{kind: :model, input: %{turn: next}}

          true ->
            complete(turn, failed(turn, guardrail, reason))
        end
    end
  end

  defp recover_or_block(turn, instruction) do
    case Budget.before_model(turn) do
      {:error, _budget, budget_reason} ->
        complete(turn, blocked(turn, :limits, budget_reason))

      :ok ->
        cond do
          turn.model_attempt <= turn.max_retries ->
            next = %{turn | repair_instruction: instruction, retries: turn.retries + 1}
            %{kind: :model, input: %{turn: next}}

          turn.model_index + 1 < length(turn.models) ->
            next = %{
              turn
              | model_index: turn.model_index + 1,
                model_attempt: 0,
                repair_instruction: instruction,
                retries: turn.retries + 1
            }

            %{kind: :model, input: %{turn: next}}

          true ->
            complete(turn, blocked(turn, :output, turn.output_reason))
        end
    end
  end

  defp review_required?(turn) do
    review = Map.get(turn, :review_tools, [])
    Enum.any?(turn.model_outcome.tool_calls, &(&1.name in review))
  end

  defp blocked(turn, guardrail, reason) do
    %{
      status: :blocked,
      output: "",
      model_calls: turn.model_calls,
      tool_rounds: turn.tool_rounds,
      tool_calls: turn.tool_call_count,
      tool_errors: turn.tool_error_count,
      retries: turn.retries,
      guardrail: guardrail,
      reason: reason
    }
  end

  defp failed(turn, guardrail, reason) do
    %{
      status: :failed,
      output: "",
      model_calls: turn.model_calls,
      tool_rounds: turn.tool_rounds,
      tool_calls: turn.tool_call_count,
      tool_errors: turn.tool_error_count,
      retries: turn.retries,
      guardrail: guardrail,
      reason: reason
    }
  end

  defp complete(turn, result), do: %{kind: :complete, output: %{turn: turn, result: result}}
end
