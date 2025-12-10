defmodule JSV.ValidationError do
  alias JSV.ErrorFormatter

  @moduledoc """
  The data structure returned by `JSV.validate/3` when validation fails.
  """

  @enforce_keys [:errors]
  defexception errors: []

  @type t :: %__MODULE__{errors: [JSV.Validator.Error.t()]}

  @doc """
  Wraps the given `JSV.Validator.Error` list into an `#{inspect(__MODULE__)}`
  exception.
  """
  @spec of([JSV.Validator.Error.t()]) :: t
  def of(errors) when is_list(errors) do
    %__MODULE__{errors: errors}
  end

  @impl true
  def message(e) do
    %{valid: false, details: units} = ErrorFormatter.normalize_error(e, keys: :atoms)
    units_fmt = format_units(units, 0)
    top_message = "json schema validation failed"
    message = [top_message, "\n\n" | units_fmt]
    IO.iodata_to_binary(message)
  end

  defp format_units(units, indent) do
    Enum.map_intersperse(units, "\n\n", &format_unit(&1, indent))
  end

  defp format_unit(unit, indent) do
    %{
      valid: valid?,
      schemaLocation: schema_location,
      instanceLocation: instance_location
    } = unit

    show_valid =
      case valid? do
        true -> [indent(indent), "valid: true", "\n"]
        false -> []
      end

    errors_annots =
      case unit do
        %{errors: list} ->
          annots = Enum.map_intersperse(list, "\n", &format_annot(&1, indent + 1))
          [indent(indent), "errors:\n" | annots]

        _ ->
          []
      end

    [
      [indent(indent), "at: ", inspect(instance_location), "\n"],
      [indent(indent), "by: ", inspect(schema_location), "\n"],
      show_valid,
      errors_annots
    ]
  end

  defp format_annot(err, indent) do
    case err do
      %{details: sub_units} ->
        [
          "#{indent(indent)}- (",
          Atom.to_string(err.kind),
          ") ",
          err.message,
          "\n\n",
          format_units(sub_units, indent + 1)
        ]

      _ ->
        ["#{indent(indent)}- (", Atom.to_string(err.kind), ") ", err.message]
    end
  end

  defp indent(n) when n > 1 do
    [indent(1), indent(n - 1)]
  end

  defp indent(1) do
    "  "
  end

  defp indent(0) do
    []
  end
end
