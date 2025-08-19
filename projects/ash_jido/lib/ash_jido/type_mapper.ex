defmodule AshJido.TypeMapper do
  @moduledoc """
  Maps Ash types to NimbleOptions schema specifications.

  This module handles the conversion from Ash type system to the type
  specifications expected by NimbleOptions in Jido actions.
  """

  @doc """
  Converts an Ash type to a NimbleOptions schema entry.

  ## Examples

      iex> AshJido.TypeMapper.ash_type_to_nimble_options(Ash.Type.String, %{allow_nil?: false})
      [type: :string, required: true]

      iex> AshJido.TypeMapper.ash_type_to_nimble_options(Ash.Type.Integer, %{allow_nil?: true})
      [type: :integer]
  """
  def ash_type_to_nimble_options(ash_type, field_config \\ %{}) do
    base_type = map_ash_type_to_nimble_type(ash_type)

    options = [type: base_type]

    options
    |> maybe_add_required(field_config)
    |> maybe_add_doc(field_config)
    |> maybe_add_default(field_config)
  end

  defp map_ash_type_to_nimble_type(ash_type) do
    case ash_type do
      Ash.Type.String ->
        :string

      Ash.Type.Integer ->
        :integer

      Ash.Type.Float ->
        :float

      # Map Decimal to float for simplicity in PoC
      Ash.Type.Decimal ->
        :float

      Ash.Type.Boolean ->
        :boolean

      Ash.Type.UUID ->
        :string

      Ash.Type.Date ->
        :string

      Ash.Type.DateTime ->
        :string

      Ash.Type.Time ->
        :string

      Ash.Type.Binary ->
        :string

      Ash.Type.Atom ->
        :atom

      # For embedded resources or complex types, default to map
      _ when is_atom(ash_type) ->
        case ash_type do
          type when type in [Ash.Type.Map, Ash.Type.Term] ->
            :map

          _ ->
            # Check if it's an embedded resource or custom type
            if function_exported?(ash_type, :storage_type, 0) do
              # Try to infer from storage type
              storage_type = ash_type.storage_type()
              map_ash_type_to_nimble_type(storage_type)
            else
              # Default to map for unknown types
              :map
            end
        end

      # Handle array types
      {:array, inner_type} ->
        {:list, map_ash_type_to_nimble_type(inner_type)}

      # Default case
      _ ->
        :map
    end
  end

  defp maybe_add_required(options, field_config) do
    case field_config do
      %{allow_nil?: false} -> Keyword.put(options, :required, true)
      %{allow_nil?: true} -> options
      _ -> options
    end
  end

  defp maybe_add_doc(options, field_config) do
    case field_config do
      %{description: description} when is_binary(description) ->
        enhanced_doc = enhance_documentation(description, field_config, options[:type])
        Keyword.put(options, :doc, enhanced_doc)

      %{name: name} ->
        # Generate documentation from field name if no description
        auto_doc = generate_auto_documentation(name, field_config, options[:type])
        Keyword.put(options, :doc, auto_doc)

      _ ->
        options
    end
  end

  # Enhance existing documentation with type hints and requirements
  defp enhance_documentation(description, field_config, type) do
    type_hint = get_type_hint(type)
    required_hint = get_required_hint(field_config)

    parts =
      [description, type_hint, required_hint]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" - ")

    parts
  end

  # Generate documentation automatically from field name and type
  defp generate_auto_documentation(name, field_config, type) do
    base_doc = humanize_field_name(name)
    type_hint = get_type_hint(type)
    required_hint = get_required_hint(field_config)

    parts =
      [base_doc, type_hint, required_hint]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" - ")

    parts
  end

  # Get helpful type hints for documentation
  defp get_type_hint(type) do
    case type do
      :string -> "Text input"
      :integer -> "Numeric value"
      :float -> "Decimal number"
      :boolean -> "True/false value"
      :atom -> "Atom value"
      :map -> "Object/map data"
      {:list, _} -> "List of values"
      _ -> ""
    end
  end

  # Get requirement status for documentation
  defp get_required_hint(field_config) do
    case field_config do
      %{allow_nil?: false} -> "(required)"
      %{allow_nil?: true} -> "(optional)"
      _ -> ""
    end
  end

  # Convert field names to human readable format
  defp humanize_field_name(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp maybe_add_default(options, field_config) do
    case field_config do
      %{default: default} when not is_nil(default) ->
        Keyword.put(options, :default, default)

      _ ->
        options
    end
  end
end
