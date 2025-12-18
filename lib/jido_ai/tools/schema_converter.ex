defmodule Jido.AI.Tools.SchemaConverter do
  @moduledoc """
  Converts Jido.Action modules to JSON Schema tool definitions for LLM APIs.

  This module transforms NimbleOptions schemas from Jido.Action modules into
  the JSON Schema format expected by OpenAI, Anthropic, and other LLM providers
  for function/tool calling.

  ## Usage

      # Convert a single action
      tool = SchemaConverter.action_to_tool(MyWeatherAction)

      # Convert multiple actions
      tools = SchemaConverter.actions_to_tools([WeatherAction, SearchAction])

  ## Supported Schema Types

  The converter handles these NimbleOptions types:

    * `:string` - JSON string
    * `:integer` - JSON integer
    * `:float` - JSON number
    * `:boolean` - JSON boolean
    * `:atom` - JSON string
    * `{:in, values}` - JSON string with enum constraint
    * `{:list, type}` - JSON array
    * `:map` - JSON object
    * `:any` - JSON any (no type constraint)
  """

  @doc """
  Converts multiple Jido.Action modules to tool definitions.

  ## Examples

      tools = SchemaConverter.actions_to_tools([WeatherAction, SearchAction])
      # => [%{type: "function", function: %{...}}, ...]
  """
  @spec actions_to_tools([module()]) :: [map()]
  def actions_to_tools(action_modules) when is_list(action_modules) do
    Enum.map(action_modules, &action_to_tool/1)
  end

  @doc """
  Converts a single Jido.Action module to a tool definition.

  ## Examples

      tool = SchemaConverter.action_to_tool(WeatherAction)
      # => %{
      #   type: "function",
      #   function: %{
      #     name: "get_weather",
      #     description: "Get weather for a location",
      #     parameters: %{type: "object", properties: %{...}, required: [...]}
      #   }
      # }
  """
  @spec action_to_tool(module()) :: map()
  def action_to_tool(action_module) do
    %{
      type: "function",
      function: %{
        name: get_action_name(action_module),
        description: get_action_description(action_module),
        parameters: schema_to_json_schema(get_action_schema(action_module))
      }
    }
  end

  @doc """
  Creates a map of action modules keyed by their tool names.

  Useful for looking up actions when executing tool calls.

  ## Examples

      action_map = SchemaConverter.build_action_map([WeatherAction, SearchAction])
      # => %{"get_weather" => WeatherAction, "search" => SearchAction}
  """
  @spec build_action_map([module()]) :: %{String.t() => module()}
  def build_action_map(action_modules) do
    Map.new(action_modules, fn module ->
      {get_action_name(module), module}
    end)
  end

  # =============================================================================
  # Private Functions - Action Introspection
  # =============================================================================

  defp get_action_name(action_module) do
    if function_exported?(action_module, :name, 0) do
      action_module.name()
    else
      action_module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
    end
  end

  defp get_action_description(action_module) do
    if function_exported?(action_module, :description, 0) do
      action_module.description()
    else
      "No description available"
    end
  end

  defp get_action_schema(action_module) do
    if function_exported?(action_module, :schema, 0) do
      action_module.schema()
    else
      []
    end
  end

  # =============================================================================
  # Private Functions - Schema Conversion
  # =============================================================================

  defp schema_to_json_schema(nimble_schema) when is_list(nimble_schema) do
    properties =
      Enum.reduce(nimble_schema, %{}, fn {key, opts}, acc ->
        Map.put(acc, to_string(key), nimble_opts_to_json_schema(opts))
      end)

    required =
      nimble_schema
      |> Enum.filter(fn {_key, opts} -> Keyword.get(opts, :required, false) end)
      |> Enum.map(fn {key, _opts} -> to_string(key) end)

    result = %{
      type: "object",
      properties: properties
    }

    if required != [] do
      Map.put(result, :required, required)
    else
      result
    end
  end

  defp schema_to_json_schema(_), do: %{type: "object", properties: %{}}

  defp nimble_opts_to_json_schema(opts) when is_list(opts) do
    type = Keyword.get(opts, :type, :string)
    doc = Keyword.get(opts, :doc, "")
    default = Keyword.get(opts, :default)

    base = build_base_schema(doc, default)
    add_type_constraints(base, type)
  end

  defp nimble_opts_to_json_schema(_), do: %{type: "string"}

  defp build_base_schema(doc, default) do
    base = %{}

    base =
      if doc && doc != "" do
        Map.put(base, :description, doc)
      else
        base
      end

    if default != nil do
      Map.put(base, :default, default)
    else
      base
    end
  end

  defp add_type_constraints(base, type) do
    case type do
      :string ->
        Map.put(base, :type, "string")

      :integer ->
        Map.put(base, :type, "integer")

      :float ->
        Map.put(base, :type, "number")

      :number ->
        Map.put(base, :type, "number")

      :boolean ->
        Map.put(base, :type, "boolean")

      :atom ->
        Map.put(base, :type, "string")

      :map ->
        Map.put(base, :type, "object")

      :any ->
        base

      {:in, values} ->
        string_values = Enum.map(values, &to_string/1)
        Map.merge(base, %{type: "string", enum: string_values})

      {:list, inner_type} ->
        inner_schema = add_type_constraints(%{}, inner_type)
        Map.merge(base, %{type: "array", items: inner_schema})

      {:or, types} ->
        # For union types, use anyOf
        any_of = Enum.map(types, fn t -> add_type_constraints(%{}, t) end)
        Map.put(base, :anyOf, any_of)

      {:custom, _module, _opts} ->
        # Custom types default to string
        Map.put(base, :type, "string")

      # Handle nested keyword schemas
      nested when is_list(nested) ->
        Map.merge(base, schema_to_json_schema(nested))

      # Default to string for unknown types
      _ ->
        Map.put(base, :type, "string")
    end
  end
end
