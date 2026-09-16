defmodule Jido.AI.Signal.EmbedResult do
  @moduledoc """
  Signal for embedding generation completion.
  """

  use Jido.Signal,
    type: "ai.embed.result",
    default_source: "/ai/embed",
    schema:
      Zoi.object(
        %{
          call_id: Zoi.string(),
          result: Zoi.any()
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
