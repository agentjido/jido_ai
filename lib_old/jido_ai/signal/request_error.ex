defmodule Jido.AI.Signal.RequestError do
  @moduledoc """
  Signal for request rejection.
  """

  use Jido.Signal,
    type: "ai.request.error",
    default_source: "/ai/strategy",
    schema:
      Zoi.object(
        %{
          request_id: Zoi.string(),
          reason: Zoi.atom(),
          message: Zoi.string()
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
