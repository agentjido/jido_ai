defmodule JSV.Resolver.Embedded.Draft202012.Meta.Applicator do
  @moduledoc false

  @deprecated "use #{inspect(__MODULE__)}.json_schema/0 instead"
  @doc false
  @spec schema :: map
  def schema do
    json_schema()
  end

  @spec json_schema :: map
  def json_schema do
    %{
      "$defs" => %{
        "schemaArray" => %{
          "items" => %{"$dynamicRef" => "#meta"},
          "minItems" => 1,
          "type" => "array"
        }
      },
      "$dynamicAnchor" => "meta",
      "$id" => "https://json-schema.org/draft/2020-12/meta/applicator",
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "properties" => %{
        "additionalProperties" => %{"$dynamicRef" => "#meta"},
        "allOf" => %{"$ref" => "#/$defs/schemaArray"},
        "anyOf" => %{"$ref" => "#/$defs/schemaArray"},
        "contains" => %{"$dynamicRef" => "#meta"},
        "dependentSchemas" => %{
          "additionalProperties" => %{"$dynamicRef" => "#meta"},
          "default" => %{},
          "type" => "object"
        },
        "else" => %{"$dynamicRef" => "#meta"},
        "if" => %{"$dynamicRef" => "#meta"},
        "items" => %{"$dynamicRef" => "#meta"},
        "not" => %{"$dynamicRef" => "#meta"},
        "oneOf" => %{"$ref" => "#/$defs/schemaArray"},
        "patternProperties" => %{
          "additionalProperties" => %{"$dynamicRef" => "#meta"},
          "default" => %{},
          "propertyNames" => %{"format" => "regex"},
          "type" => "object"
        },
        "prefixItems" => %{"$ref" => "#/$defs/schemaArray"},
        "properties" => %{
          "additionalProperties" => %{"$dynamicRef" => "#meta"},
          "default" => %{},
          "type" => "object"
        },
        "propertyNames" => %{"$dynamicRef" => "#meta"},
        "then" => %{"$dynamicRef" => "#meta"}
      },
      "title" => "Applicator vocabulary meta-schema",
      "type" => ["object", "boolean"]
    }
  end
end
