defmodule JSV.ErrorFormatter.ValidationUnitSchema do
  use JSV.Schema

  @moduledoc false

  defschema %{
    type: :object,
    title: "JSV:ValidationUnit",
    description: ~SD"""
    Describes all errors found at given instanceLocation raised by the same
    sub-schema (same schemaLocation and evaluationPath).

    It may also represent a positive validation result, (when `valid` is `true`)
    needed when for instance multiple schemas under `oneOf` validates the input
    sucessfully.
    """,
    properties: %{
      valid: boolean(),
      schemaLocation:
        string(
          description: ~SD"""
          A JSON path pointing to the part of the schema that invalidated the data.
          """
        ),
      evaluationPath:
        string(
          description: ~SD"""
          A JSON path pointing to the part of the schema that invalidated the data,
          but going through all indirections like $ref within the schema, starting
          from the root schema.
          """
        ),
      instanceLocation:
        string(
          description: ~SD"""
          A JSON path pointing to the invalid part in the input data.
          """
        ),
      errors: array_of(JSV.ErrorFormatter.KeywordErrorSchema)
    },
    required: [:valid]
  }
end
