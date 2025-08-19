defmodule AshJido.Mapper do
  @moduledoc """
  Handles conversion of Ash results to Jido-compatible formats.

  This module is responsible for:
  - Converting Ash structs to maps when requested
  - Preserving pagination metadata
  - Wrapping errors in Jido.Error format
  """

  @doc """
  Wraps an Ash result according to the Jido action configuration.

  ## Examples

      iex> AshJido.Mapper.wrap_result({:ok, %User{id: 1, name: "John"}}, %{output_map?: true})
      {:ok, %{id: 1, name: "John"}}

      iex> AshJido.Mapper.wrap_result({:error, %Ash.Error{}}, %{})
      {:error, %Jido.Error{}}
  """
  def wrap_result(ash_result, jido_config \\ %{}) do
    case ash_result do
      {:ok, data} ->
        converted_data = maybe_convert_to_maps(data, jido_config)
        {:ok, converted_data}

      {:error, ash_error} when is_exception(ash_error) ->
        jido_error = convert_ash_error_to_jido_error(ash_error)
        {:error, jido_error}

      {:error, error} ->
        {:error, error}

      # Handle direct data (for some Ash operations)
      data when not is_tuple(data) ->
        converted_data = maybe_convert_to_maps(data, jido_config)
        {:ok, converted_data}
    end
  end

  defp maybe_convert_to_maps(data, %{output_map?: false}), do: data
  defp maybe_convert_to_maps(data, _config), do: convert_to_maps(data)

  defp convert_to_maps(data) when is_list(data) do
    Enum.map(data, &convert_to_maps/1)
  end

  defp convert_to_maps(%_{} = struct) do
    if is_ash_resource?(struct) do
      struct_to_map(struct)
    else
      struct
    end
  end

  defp convert_to_maps(data), do: data

  defp is_ash_resource?(struct) do
    # Check if the struct is an Ash resource
    module = struct.__struct__

    # Check if it's an Ash resource by looking for the spark_dsl_config function
    function_exported?(module, :spark_dsl_config, 0)
  rescue
    _ -> false
  end

  defp struct_to_map(struct) do
    # Convert Ash resource struct to map with only the attributes
    try do
      resource = struct.__struct__

      # Get attributes from the DSL configuration
      dsl_state = resource.spark_dsl_config()
      attributes = Spark.Dsl.Extension.get_entities(dsl_state, [:attributes])

      Enum.reduce(attributes, %{}, fn attr, acc ->
        value = Map.get(struct, attr.name)
        Map.put(acc, attr.name, convert_to_maps(value))
      end)
    rescue
      _ ->
        # Fallback: convert struct to map using all keys, excluding special Ash keys
        struct
        |> Map.from_struct()
        |> Enum.reject(fn {k, v} ->
          is_function(v) or
            k in [
              :__meta__,
              :__metadata__,
              :aggregates,
              :calculations,
              :__order__,
              :__lateral_join_source__
            ]
        end)
        |> Map.new()
    end
  end

  defp convert_ash_error_to_jido_error(ash_error) when is_exception(ash_error) do
    # Convert Ash error classes to appropriate Jido error types
    {error_type, jido_type} = classify_ash_error(ash_error)

    # Extract detailed error information
    error_details = extract_error_details(ash_error)

    # Create structured Jido error
    %Jido.Error{
      type: jido_type,
      message: Exception.message(ash_error),
      details: %{
        ash_error_class: error_type,
        ash_error: ash_error,
        underlying_errors: error_details.underlying_errors,
        fields: error_details.fields,
        changeset_errors: error_details.changeset_errors
      }
    }
  rescue
    # Fallback if Jido.Error structure is different or creation fails
    _ ->
      %{
        type: :execution_error,
        message: Exception.message(ash_error),
        ash_error: ash_error
      }
  end

  # Classify Ash errors into appropriate Jido error types
  defp classify_ash_error(ash_error) do
    case ash_error do
      %{__struct__: module} ->
        case module do
          # Authorization/Permission errors
          Ash.Error.Forbidden ->
            {:forbidden, :authorization_error}

          # Validation/Input errors
          Ash.Error.Invalid ->
            {:invalid, :validation_error}

          # Framework/System errors  
          Ash.Error.Framework ->
            {:framework, :system_error}

          # Unknown/Unexpected errors
          Ash.Error.Unknown ->
            {:unknown, :execution_error}

          # Handle other error types
          _ ->
            module_name = module |> Module.split() |> Enum.join(".")

            if String.starts_with?(module_name, "Ash.") do
              {:ash_error, :execution_error}
            else
              {:other, :execution_error}
            end
        end

      _ ->
        {:unknown, :execution_error}
    end
  end

  # Extract detailed error information from Ash errors
  defp extract_error_details(ash_error) do
    underlying_errors = extract_underlying_errors(ash_error)
    fields = extract_field_errors(underlying_errors)
    changeset_errors = extract_changeset_errors(underlying_errors)

    %{
      underlying_errors: underlying_errors,
      fields: fields,
      changeset_errors: changeset_errors
    }
  end

  # Extract underlying errors from Ash error structs
  defp extract_underlying_errors(ash_error) do
    cond do
      Map.has_key?(ash_error, :errors) and is_list(ash_error.errors) ->
        ash_error.errors

      Map.has_key?(ash_error, :error) ->
        [ash_error.error]

      true ->
        []
    end
  end

  # Extract field-specific errors for validation feedback
  defp extract_field_errors(underlying_errors) do
    underlying_errors
    |> Enum.flat_map(fn error ->
      case error do
        # Changeset errors often have field information
        %{field: field, message: message} when not is_nil(field) ->
          [{field, message}]

        # Validation errors may have path information
        %{path: path, message: message} when is_list(path) and length(path) > 0 ->
          field = path |> List.last()
          [{field, message}]

        _ ->
          []
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  # Extract changeset-specific error information
  defp extract_changeset_errors(underlying_errors) do
    underlying_errors
    |> Enum.filter(fn error ->
      case error do
        %{__struct__: module} ->
          module_name = module |> Module.split() |> Enum.join(".")

          String.contains?(module_name, "Changeset") or
            String.contains?(module_name, "Validation")

        _ ->
          false
      end
    end)
    |> Enum.map(fn error ->
      %{
        type: error.__struct__,
        message: Exception.message(error),
        details: Map.from_struct(error)
      }
    end)
  end
end
