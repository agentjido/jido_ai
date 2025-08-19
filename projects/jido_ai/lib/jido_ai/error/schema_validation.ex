defmodule Jido.AI.Error.SchemaValidation do
  @moduledoc """
  Error for schema validation failures during structured data generation.

  This error is raised when the generated structured data fails to validate against
  the provided schema, such as missing required fields, incorrect types, or
  constraint violations.
  """

  use Splode.Error,
    fields: [:text, :response, :usage, :cause, :schema, :validation_errors],
    class: :invalid

  @type t :: %__MODULE__{
          text: String.t() | nil,
          response: map() | nil,
          usage: map() | nil,
          cause: term() | nil,
          schema: map() | nil,
          validation_errors: list() | nil
        }

  def message(%{validation_errors: errors, schema: schema}) when is_list(errors) and not is_nil(schema) do
    error_summary = format_validation_errors(errors)
    "Schema validation failed: #{error_summary}"
  end

  def message(%{cause: cause}) when not is_nil(cause) do
    "Schema validation failed: #{inspect(cause)}"
  end

  def message(_) do
    "Schema validation failed: generated data does not conform to expected schema"
  end

  defp format_validation_errors([]), do: "unknown validation errors"

  defp format_validation_errors(errors) when is_list(errors) do
    errors
    |> Enum.take(3)
    |> Enum.map_join(", ", &format_single_error/1)
    |> then(fn summary ->
      if length(errors) > 3 do
        "#{summary} (and #{length(errors) - 3} more)"
      else
        summary
      end
    end)
  end

  defp format_validation_errors(_), do: "invalid validation error format"

  defp format_single_error(%{field: field, message: message}) when is_binary(field) and is_binary(message) do
    "#{field}: #{message}"
  end

  defp format_single_error(%{path: path, message: message}) when is_list(path) and is_binary(message) do
    path_str = Enum.join(path, ".")
    "#{path_str}: #{message}"
  end

  defp format_single_error(error) when is_binary(error) do
    error
  end

  defp format_single_error(error) do
    inspect(error)
  end
end
