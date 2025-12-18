defmodule JSV.ErrorFormatter.ValidationErrorSchema do
  require JSV.ErrorFormatter.ValidationUnitSchema
  use JSV.Schema

  @moduledoc false

  defschema %{
    type: :object,
    title: "JSV:ValidationError",
    description: ~SD"""
    This represents a normalized `JSV.ValidationError` in a JSON-encodable way.

    It contains a list of error units.
    """,
    properties: %{
      valid: %{const: false},
      details: array_of(JSV.ErrorFormatter.ValidationUnitSchema)
    },
    required: [:valid]
  }
end
