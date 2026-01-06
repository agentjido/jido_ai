defmodule Jido.AI.Skills.ToolCalling.Actions.ListTools do
  @moduledoc """
  A Jido.Action for listing all available tools with their schemas.

  This action queries the `Jido.AI.Tools.Registry` and returns information
  about all registered tools, including their names, types, and schemas.

  ## Parameters

  * `filter` (optional) - Filter tools by name pattern (string)
  * `type` (optional) - Filter by type (`:action`, `:tool`, or `nil` for all)
  * `include_schema` (optional) - Include tool schemas (default: `true`)

  ## Examples

      # List all tools
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.ToolCalling.Actions.ListTools, %{})

      # Filter by name pattern
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.ToolCalling.Actions.ListTools, %{
        filter: "calc"
      })

      # List only actions
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.ToolCalling.Actions.ListTools, %{
        type: :action
      })
  """

  use Jido.Action,
    name: "tool_calling_list_tools",
    description: "List all available tools with their schemas",
    category: "ai",
    tags: ["tool-calling", "discovery", "tools"],
    vsn: "1.0.0",
    schema: [
      filter: [
        type: :string,
        required: false,
        doc: "Filter tools by name pattern (substring match)"
      ],
      type: [
        type: :atom,
        required: false,
        doc: "Filter by type (:action, :tool, or nil for all)"
      ],
      include_schema: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Include tool schemas in result"
      ]
    ]

  alias Jido.AI.Tools.Registry

  @doc """
  Executes the list tools action.
  """
  @impl Jido.Action
  def run(params, _context) do
    Registry.ensure_started()

    tools =
      Registry.list_all()
      |> filter_tools(params[:filter], params[:type])
      |> format_tools(params[:include_schema] != false)

    {:ok,
     %{
       tools: tools,
       count: length(tools),
       filter: params[:filter],
       type: params[:type]
     }}
  end

  # Private Functions

  defp filter_tools(tools, nil, nil), do: tools
  defp filter_tools(tools, filter, type), do: filter_tools(tools, filter, type, [])

  defp filter_tools([], _filter, _type, acc), do: Enum.reverse(acc)

  defp filter_tools([{name, tool_type, module} | rest], filter, type, acc) do
    matches_filter = filter == nil or String.contains?(name, filter)
    matches_type = type == nil or tool_type == type

    if matches_filter and matches_type do
      filter_tools(rest, filter, type, [{name, tool_type, module} | acc])
    else
      filter_tools(rest, filter, type, acc)
    end
  end

  defp format_tools(tools, include_schema) do
    Enum.map(tools, fn {name, type, module} ->
      base = %{
        name: name,
        type: type,
        module: module
      }

      if include_schema do
        Map.put(base, :schema, extract_schema(module))
      else
        base
      end
    end)
  end

  defp extract_schema(module) do
    try do
      case module.schema() do
        schema when is_list(schema) ->
          format_schema_list(schema)

        schema when is_map(schema) ->
          format_schema_map(schema)

        _ ->
          nil
      end
    rescue
      _ -> nil
    end
  end

  defp format_schema_list(schema) when is_list(schema) do
    Enum.map(schema, fn {key, opts} ->
      %{
        name: key,
        type: Keyword.get(opts, :type),
        required: Keyword.get(opts, :required, false),
        default: Keyword.get(opts, :default),
        doc: Keyword.get(opts, :doc)
      }
    end)
  end

  defp format_schema_list(_), do: nil

  defp format_schema_map(_schema), do: nil
end
