defmodule Jido.AI.Runner.GEPA.Scheduler.Task do
  @moduledoc """
  Task structure for scheduled evaluations.

  Represents an evaluation task with priority, status tracking, and execution metadata.
  """

  use TypedStruct

  @type priority :: :critical | :high | :normal | :low
  @type status :: :pending | :running | :completed | :failed | :cancelled

  typedstruct do
    field(:id, String.t(), enforce: true)
    field(:candidate_id, String.t(), enforce: true)
    field(:priority, priority(), default: :normal)
    field(:evaluator, function(), enforce: true)
    field(:metadata, map(), default: %{})
    field(:status, status(), default: :pending)
    field(:result, term())
    field(:submitted_at, integer(), enforce: true)
    field(:started_at, integer())
    field(:completed_at, integer())
  end
end
