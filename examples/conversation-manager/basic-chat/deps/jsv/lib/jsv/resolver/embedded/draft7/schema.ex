defmodule JSV.Resolver.Embedded.Draft7.Schema do
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
      "$id" => "http://json-schema.org/draft-07/schema#",
      "$schema" => "http://json-schema.org/draft-07/schema#",
      "default" => true,
      "definitions" => %{
        "nonNegativeInteger" => %{"minimum" => 0, "type" => "integer"},
        "nonNegativeIntegerDefault0" => %{
          "allOf" => [
            %{"$ref" => "#/definitions/nonNegativeInteger"},
            %{"default" => 0}
          ]
        },
        "schemaArray" => %{
          "items" => %{"$ref" => "#"},
          "minItems" => 1,
          "type" => "array"
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
      "properties" => %{
        "additionalItems" => %{"$ref" => "#"},
        "pattern" => %{"format" => "regex", "type" => "string"},
        "propertyNames" => %{"$ref" => "#"},
        "minLength" => %{"$ref" => "#/definitions/nonNegativeIntegerDefault0"},
        "allOf" => %{"$ref" => "#/definitions/schemaArray"},
        "oneOf" => %{"$ref" => "#/definitions/schemaArray"},
        "type" => %{
          "anyOf" => [
            %{"$ref" => "#/definitions/simpleTypes"},
            %{
              "items" => %{"$ref" => "#/definitions/simpleTypes"},
              "minItems" => 1,
              "type" => "array",
              "uniqueItems" => true
            }
          ]
        },
        "contentMediaType" => %{"type" => "string"},
        "maxItems" => %{"$ref" => "#/definitions/nonNegativeInteger"},
        "patternProperties" => %{
          "additionalProperties" => %{"$ref" => "#"},
          "default" => %{},
          "propertyNames" => %{"format" => "regex"},
          "type" => "object"
        },
        "contentEncoding" => %{"type" => "string"},
        "items" => %{
          "anyOf" => [%{"$ref" => "#"}, %{"$ref" => "#/definitions/schemaArray"}],
          "default" => true
        },
        "properties" => %{
          "additionalProperties" => %{"$ref" => "#"},
          "default" => %{},
          "type" => "object"
        },
        "maxProperties" => %{"$ref" => "#/definitions/nonNegativeInteger"},
        "not" => %{"$ref" => "#"},
        "else" => %{"$ref" => "#"},
        "contains" => %{"$ref" => "#"},
        "if" => %{"$ref" => "#"},
        "writeOnly" => %{"default" => false, "type" => "boolean"},
        "exclusiveMinimum" => %{"type" => "number"},
        "multipleOf" => %{"exclusiveMinimum" => 0, "type" => "number"},
        "format" => %{"type" => "string"},
        "description" => %{"type" => "string"},
        "examples" => %{"items" => true, "type" => "array"},
        "$ref" => %{"format" => "uri-reference", "type" => "string"},
        "minProperties" => %{"$ref" => "#/definitions/nonNegativeIntegerDefault0"},
        "readOnly" => %{"default" => false, "type" => "boolean"},
        "maxLength" => %{"$ref" => "#/definitions/nonNegativeInteger"},
        "$comment" => %{"type" => "string"},
        "enum" => %{
          "items" => true,
          "minItems" => 1,
          "type" => "array",
          "uniqueItems" => true
        },
        "const" => true,
        "maximum" => %{"type" => "number"},
        "uniqueItems" => %{"default" => false, "type" => "boolean"},
        "minItems" => %{"$ref" => "#/definitions/nonNegativeIntegerDefault0"},
        "$schema" => %{"format" => "uri", "type" => "string"},
        "then" => %{"$ref" => "#"},
        "required" => %{"$ref" => "#/definitions/stringArray"},
        "minimum" => %{"type" => "number"},
        "exclusiveMaximum" => %{"type" => "number"},
        "additionalProperties" => %{"$ref" => "#"},
        "title" => %{"type" => "string"},
        "dependencies" => %{
          "additionalProperties" => %{
            "anyOf" => [%{"$ref" => "#"}, %{"$ref" => "#/definitions/stringArray"}]
          },
          "type" => "object"
        },
        "anyOf" => %{"$ref" => "#/definitions/schemaArray"},
        "$id" => %{"format" => "uri-reference", "type" => "string"},
        "default" => true,
        "definitions" => %{
          "additionalProperties" => %{"$ref" => "#"},
          "default" => %{},
          "type" => "object"
        }
      },
      "title" => "Core schema meta-schema",
      "type" => ["object", "boolean"]
    }
  end
end
