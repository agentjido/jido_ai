defmodule Jido.AI.Signal.Step do
  @moduledoc """
  Signal for ReAct step tracking.
  """

  use Jido.Signal,
    type: "ai.react.step",
    default_source: "/ai/react/step",
    schema: [
      step_id: [type: :string, required: true, doc: "Unique step identifier"],
      call_id: [type: :string, required: true, doc: "Root request correlation ID"],
      step_type: [type: :atom, required: true, doc: "Step type: :thought, :action, :observation, :final"],
      content: [type: :any, required: true, doc: "Step content"],
      parent_step_id: [type: :string, doc: "Parent step for nested reasoning"],
      at_ms: [type: :integer, doc: "Timestamp when step occurred"]
    ]
end
