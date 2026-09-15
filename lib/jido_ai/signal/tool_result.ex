defmodule Jido.AI.Signal.ToolResult do
  @moduledoc """
  Signal for tool execution completion.
  """

  use Jido.Signal,
    type: "ai.tool.result",
    default_source: "/ai/tool",
    schema:
      Zoi.object(
        %{
          call_id: Zoi.string(),
          tool_name: Zoi.string(),
          result: Zoi.any(),
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
  def to_json, do: Jido.AI.Signal.Definition.metadata(__MODULE__)
  def __signal_metadata__, do: to_json()
end
