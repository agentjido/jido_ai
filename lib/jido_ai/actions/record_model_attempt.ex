defmodule Jido.AI.Actions.RecordModelAttempt do
  @moduledoc "Records one model attempt and any accepted assistant message."

  alias Jido.AI.{Conversation, Runtime, Thread.Projection}

  use Jido.Action,
    name: "jido_ai_record_model_attempt",
    description: "Record a model attempt in the canonical Session",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn, outcome: %{status: :budget} = outcome} = params, _context) do
    {:ok,
     %{
       turn:
         turn
         |> Map.put(:model_outcome, outcome)
         |> Map.put(:output_allowed, params.output_allowed)
         |> Map.put(:output_reason, params.output_reason)
     }}
  end

  def run(params, context) do
    turn = params.turn
    outcome = params.outcome
    at = Runtime.now_ms(context)
    refs = %{request_id: turn.request_id, run_id: turn.run_id}

    attempt = %{
      status: outcome.status,
      model: outcome.model,
      model_index: turn.model_index,
      model_call: turn.model_calls,
      model_attempt: turn.model_attempt,
      tool_rounds: turn.tool_rounds,
      output_allowed: params.output_allowed,
      output_reason: params.output_reason,
      outcome: portable_outcome(outcome),
      prompt_cache: params.prompt_cache
    }

    session =
      turn.session
      |> Conversation.decode!()
      |> Projection.observe(:ai_model_attempt, attempt, refs, at)

    with {:ok, session} <- maybe_append_assistant(session, outcome, params.output_allowed, refs, at) do
      {:ok,
       %{
         turn:
           turn
           |> Map.put(:session, Conversation.encode(session))
           |> Map.update!(:model_attempts, &(&1 ++ [attempt]))
           |> Map.put(:model_outcome, outcome)
           |> Map.put(:output_allowed, params.output_allowed)
           |> Map.put(:output_reason, params.output_reason)
       }}
    end
  end

  defp maybe_append_assistant(session, %{status: :ok} = outcome, true, refs, at) do
    Projection.append(
      session,
      %{
        role: :assistant,
        content: outcome.text,
        tool_calls: outcome.tool_calls,
        metadata: %{
          response_id: outcome.response_id,
          model: outcome.model,
          finish_reason: outcome.finish_reason,
          usage: outcome.usage
        }
      },
      refs,
      at
    )
  end

  defp maybe_append_assistant(session, _outcome, _allowed, _refs, _at), do: {:ok, session}

  defp portable_outcome(%{status: :ok} = outcome) do
    Map.take(outcome, [
      :status,
      :kind,
      :finish_reason,
      :text,
      :tool_calls,
      :response_id,
      :model,
      :usage,
      :started_at_ms,
      :completed_at_ms
    ])
  end

  defp portable_outcome(outcome) do
    Map.take(outcome, [
      :status,
      :category,
      :retryable,
      :reason,
      :model,
      :usage,
      :started_at_ms,
      :completed_at_ms
    ])
  end
end
