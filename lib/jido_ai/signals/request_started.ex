defmodule Jido.AI.Signal.RequestStarted do
  @moduledoc """
  Signal for request lifecycle start.
  """

  use Jido.Signal,
    type: "ai.request.started",
    default_source: "/ai/request",
    schema:
      Zoi.object(
        %{
          request_id: Zoi.string(),
          query: Jido.AI.Query.schema(),
          run_id: Zoi.string() |> Zoi.optional()
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
