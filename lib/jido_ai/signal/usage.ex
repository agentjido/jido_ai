defmodule Jido.AI.Signal.Usage do
  @moduledoc """
  Signal for token usage and cost tracking.
  """

  use Jido.Signal,
    type: "ai.usage",
    default_source: "/ai/usage",
    schema:
      Zoi.object(
        %{
          call_id: Zoi.string(),
          model: Zoi.string(),
          input_tokens: Zoi.integer(),
          output_tokens: Zoi.integer(),
          total_tokens: Zoi.integer() |> Zoi.optional(),
          duration_ms: Zoi.integer() |> Zoi.optional(),
          metadata:
            Zoi.any()
            |> Zoi.refine({Jido.AI.Signal.Definition, :map_value, []})
            |> Zoi.default(%{})
        },
        unrecognized_keys: :error
      )

  defoverridable validate_data: 1

  def validate_data(data) do
    Jido.AI.Signal.Definition.validate_data(data, schema())
  end

  def extension_policy, do: %{}
  @doc "Returns this Signal's definition metadata as a map."
  def to_json, do: Jido.AI.Signal.Definition.metadata(__MODULE__)
  def __signal_metadata__, do: to_json()
end
