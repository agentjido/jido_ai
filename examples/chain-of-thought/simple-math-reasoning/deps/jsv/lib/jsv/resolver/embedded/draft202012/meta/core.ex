defmodule JSV.Resolver.Embedded.Draft202012.Meta.Core do
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
        "anchorString" => %{
          "pattern" => "^[A-Za-z_][-A-Za-z0-9._]*$",
          "type" => "string"
        },
        "uriReferenceString" => %{"format" => "uri-reference", "type" => "string"},
        "uriString" => %{"format" => "uri", "type" => "string"}
      },
      "$dynamicAnchor" => "meta",
      "$id" => "https://json-schema.org/draft/2020-12/meta/core",
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "properties" => %{
        "$anchor" => %{"$ref" => "#/$defs/anchorString"},
        "$comment" => %{"type" => "string"},
        "$defs" => %{
          "additionalProperties" => %{"$dynamicRef" => "#meta"},
          "type" => "object"
        },
        "$dynamicAnchor" => %{"$ref" => "#/$defs/anchorString"},
        "$dynamicRef" => %{"$ref" => "#/$defs/uriReferenceString"},
        "$id" => %{
          "$comment" => "Non-empty fragments not allowed.",
          "$ref" => "#/$defs/uriReferenceString",
          "pattern" => "^[^#]*#?$"
        },
        "$ref" => %{"$ref" => "#/$defs/uriReferenceString"},
        "$schema" => %{"$ref" => "#/$defs/uriString"},
        "$vocabulary" => %{
          "additionalProperties" => %{"type" => "boolean"},
          "propertyNames" => %{"$ref" => "#/$defs/uriString"},
          "type" => "object"
        }
      },
      "title" => "Core vocabulary meta-schema",
      "type" => ["object", "boolean"]
    }
  end
end
