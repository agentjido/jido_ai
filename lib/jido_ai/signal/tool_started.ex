defmodule Jido.AI.Signal.ToolStarted do
  @moduledoc """
  Signal emitted when a tool execution starts.
  """

  use Jido.Signal,
    type: "ai.tool.started",
    default_source: "/ai/tool",
    schema:
      Zoi.object(
        %{
          call_id: Zoi.string(),
          tool_name: Zoi.string(),
          arguments: Zoi.any() |> Zoi.optional(),
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
