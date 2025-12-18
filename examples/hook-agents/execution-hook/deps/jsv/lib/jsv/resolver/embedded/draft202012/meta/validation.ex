defmodule JSV.Resolver.Embedded.Draft202012.Meta.Validation do
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
        "nonNegativeInteger" => %{"minimum" => 0, "type" => "integer"},
        "nonNegativeIntegerDefault0" => %{
          "$ref" => "#/$defs/nonNegativeInteger",
          "default" => 0
        },
        "simpleTypes" => %{
          "enum" => ["array", "boolean", "integer", "null", "number", "object", "string"]
        },
        "stringArray" => %{
          "default" => [],
          "items" => %{"type" => "string"},
          "type" => "array",
          "uniqueItems" => true
        }
      },
      "$dynamicAnchor" => "meta",
      "$id" => "https://json-schema.org/draft/2020-12/meta/validation",
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "properties" => %{
        "const" => true,
        "dependentRequired" => %{
          "additionalProperties" => %{"$ref" => "#/$defs/stringArray"},
          "type" => "object"
        },
        "enum" => %{"items" => true, "type" => "array"},
        "exclusiveMaximum" => %{"type" => "number"},
        "exclusiveMinimum" => %{"type" => "number"},
        "maxContains" => %{"$ref" => "#/$defs/nonNegativeInteger"},
        "maxItems" => %{"$ref" => "#/$defs/nonNegativeInteger"},
        "maxLength" => %{"$ref" => "#/$defs/nonNegativeInteger"},
        "maxProperties" => %{"$ref" => "#/$defs/nonNegativeInteger"},
        "maximum" => %{"type" => "number"},
        "minContains" => %{"$ref" => "#/$defs/nonNegativeInteger", "default" => 1},
        "minItems" => %{"$ref" => "#/$defs/nonNegativeIntegerDefault0"},
        "minLength" => %{"$ref" => "#/$defs/nonNegativeIntegerDefault0"},
        "minProperties" => %{"$ref" => "#/$defs/nonNegativeIntegerDefault0"},
        "minimum" => %{"type" => "number"},
        "multipleOf" => %{"exclusiveMinimum" => 0, "type" => "number"},
        "pattern" => %{"format" => "regex", "type" => "string"},
        "required" => %{"$ref" => "#/$defs/stringArray"},
        "type" => %{
          "anyOf" => [
            %{"$ref" => "#/$defs/simpleTypes"},
            %{
              "items" => %{"$ref" => "#/$defs/simpleTypes"},
              "minItems" => 1,
              "type" => "array",
              "uniqueItems" => true
            }
          ]
        },
        "uniqueItems" => %{"default" => false, "type" => "boolean"}
      },
      "title" => "Validation vocabulary meta-schema",
      "type" => ["object", "boolean"]
    }
  end
end
