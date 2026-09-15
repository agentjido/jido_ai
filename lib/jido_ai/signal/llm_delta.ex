defmodule Jido.AI.Signal.LLMDelta do
  @moduledoc """
  Signal for streaming LLM token chunks.
  """

  use Jido.Signal,
    type: "ai.llm.delta",
    default_source: "/ai/llm",
    schema:
      Zoi.object(
        %{
          call_id: Zoi.string(),
          delta: Zoi.any(),
          chunk_type: Zoi.atom() |> Zoi.default(:content),
          metadata:
            Zoi.any()
            |> Zoi.refine({Jido.AI.Signal.Definition, :map_value, []})
            |> Zoi.default(%{}),
          seq: Zoi.integer() |> Zoi.optional(),
          run_id: Zoi.string() |> Zoi.optional(),
          request_id: Zoi.string() |> Zoi.optional(),
          iteration: Zoi.integer() |> Zoi.optional()
        },
        unrecognized_keys: :error
      )

  defoverridable validate_data: 1

  def validate_data(data) do
    Jido.AI.Signal.Definition.validate_data(data, schema())
  end

  def extension_policy, do: %{}
  def to_json, do: Jido.AI.Signal.Definition.metadata(__MODULE__)
  def __signal_metadata__, do: to_json()
end
