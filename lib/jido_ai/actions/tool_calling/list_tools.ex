defmodule Jido.AI.Actions.ToolCalling.ListTools do
  @moduledoc """
  A Jido.Action for listing all available tools with their schemas.

  This action reads tools from action context (`context[:tools]`) and returns
  information about available Action modules, including their names and schemas.

  ## Parameters

  * `filter` (optional) - Filter tools by name pattern (string)
  * `include_schema` (optional) - Include tool schemas (default: `true`)

  ## Examples

      # List all tools
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.ToolCalling.ListTools, %{})

      # Filter by name pattern
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.ToolCalling.ListTools, %{
        filter: "calc"
      })
  """

  use Jido.Action,
    name: "tool_calling_list_tools",
    description: "List all available tools with their schemas",
    category: "ai",
    tags: ["tool-calling", "discovery", "tools"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        filter:
          Zoi.string(description: "Filter tools by name pattern (substring match)")
          |> Zoi.optional(),
        include_schema: Zoi.boolean(description: "Include tool schemas in result") |> Zoi.default(true),
        include_sensitive:
          Zoi.boolean(description: "Include tools marked as sensitive (default: false)")
          |> Zoi.default(false),
        allowed_tools:
          Zoi.list(Zoi.string(), description: "Allowlist of tool names to include (all others excluded)")
          |> Zoi.optional()
      })

  alias Jido.AI.Security

  @doc """
  Executes the list tools action.
  """
  @impl Jido.Action
  def run(params, context) do
    with {:ok, validated_params} <- validate_and_sanitize_params(params) do
      # Get tools from context - expects %{tools: %{name => module}} or list
      tools_input = context[:tools] || %{}
      all_tools = normalize_tools_to_list(tools_input)

      tools =
        all_tools
        |> filter_sensitive_tools(validated_params[:include_sensitive])
        |> filter_by_allowlist(validated_params[:allowed_tools])
        |> filter_by_name(validated_params[:filter])
        |> format_tools(validated_params[:include_schema] != false)

      {:ok,
       %{
         tools: tools,
         count: length(tools),
         filter: validated_params[:filter],
         sensitive_excluded: not (validated_params[:include_sensitive] == true)
       }}
    end
  end

  defp normalize_tools_to_list(tools) when is_map(tools) do
    Enum.map(tools, fn {name, module} -> {name, module} end)
  end

  defp normalize_tools_to_list(tools) when is_list(tools) do
    Enum.map(tools, fn module -> {module.name(), module} end)
  end

  defp normalize_tools_to_list(_), do: []

  # Private Functions

  defp validate_and_sanitize_params(params) do
    with {:ok, _filter} <- validate_filter_if_present(params[:filter]),
         {:ok, _allowed} <- validate_allowed_tools_if_present(params[:allowed_tools]) do
      {:ok, params}
    end
  end

  defp validate_filter_if_present(nil), do: {:ok, nil}

  defp validate_filter_if_present(filter) when is_binary(filter) do
    Security.validate_string(filter, max_length: 1000, allow_empty: true)
  end

  defp validate_filter_if_present(_), do: {:error, :invalid_filter}

  defp validate_allowed_tools_if_present(nil), do: {:ok, nil}

  defp validate_allowed_tools_if_present(allowed) when is_list(allowed) do
    if Enum.all?(allowed, &is_binary/1) do
      {:ok, allowed}
    else
      {:error, :invalid_allowed_tools}
    end
  end

  defp validate_allowed_tools_if_present(_), do: {:error, :invalid_allowed_tools}

  # Filter out sensitive tools unless explicitly requested
  defp filter_sensitive_tools(tools, true), do: tools

  defp filter_sensitive_tools(tools, _include_sensitive) when is_list(tools) do
    Enum.filter(tools, fn {name, _module} ->
      not sensitive_tool?(name)
    end)
  end

  # Tools that should be excluded by default
  defp sensitive_tool?(name) when is_binary(name) do
    lower_name = String.downcase(name)

    Enum.any?(
      [
        "system",
        "admin",
        "config",
        "registry",
        "exec",
        "shell",
        "file",
        "delete",
        "destroy",
        "secret",
        "password",
        "token",
        "auth"
      ],
      fn keyword -> String.contains?(lower_name, keyword) end
    )
  end

  defp filter_by_allowlist(tools, nil), do: tools

  defp filter_by_allowlist(tools, allowed_tools) when is_list(allowed_tools) do
    allowed_set = MapSet.new(allowed_tools)

    Enum.filter(tools, fn {name, _module} ->
      MapSet.member?(allowed_set, name)
    end)
  end

  defp filter_by_name(tools, nil), do: tools

  defp filter_by_name(tools, filter) when is_binary(filter) do
    Enum.filter(tools, fn {name, _module} ->
      String.contains?(name, filter)
    end)
  end

  defp format_tools(tools, include_schema) do
    Enum.map(tools, fn {name, module} ->
      base = %{name: name}

      if include_schema do
        Map.put(base, :schema, extract_schema(module))
      else
        base
      end
    end)
  end

  defp extract_schema(module) do
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

  defp format_schema_map(schema) do
    schema
    |> extract_schema_fields()
    |> Enum.map(fn {name, field_schema} ->
      {inner_schema, default} = unwrap_default(field_schema)
      doc = schema_description(field_schema, inner_schema)

      %{
        name: name,
        type: schema_type(inner_schema),
        required: schema_required?(field_schema, default),
        default: default,
        doc: doc
      }
    end)
  end

  defp extract_schema_fields(%{fields: fields}) when is_list(fields), do: fields
  defp extract_schema_fields(%{fields: fields}) when is_map(fields), do: Map.to_list(fields)
  defp extract_schema_fields(_), do: []

  defp unwrap_default(%{__struct__: Zoi.Types.Default} = schema) do
    schema_map = Map.from_struct(schema)
    {schema_map.inner, schema_map.value}
  end

  defp unwrap_default(schema), do: {schema, nil}

  defp schema_required?(_schema, default) when not is_nil(default), do: false

  defp schema_required?(schema, _default) do
    case schema_meta(schema, :required) do
      true -> true
      _ -> false
    end
  end

  defp schema_description(schema, inner_schema) do
    schema_meta(schema, :description) || schema_meta(inner_schema, :description)
  end

  defp schema_meta(%{meta: meta}, key) when is_map(meta), do: Map.get(meta, key)
  defp schema_meta(_schema, _key), do: nil

  defp schema_type(%{__struct__: Zoi.Types.Array} = schema) do
    inner_type =
      schema
      |> Map.from_struct()
      |> Map.get(:inner)
      |> schema_type()

    "array(#{inner_type})"
  end

  defp schema_type(%{__struct__: struct_module}) do
    struct_module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  defp schema_type(_), do: nil
end
