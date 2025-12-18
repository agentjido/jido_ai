defmodule JSV.Resolver.Embedded.Draft202012.Schema do
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
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "$id" => "https://json-schema.org/draft/2020-12/schema",
      "$comment" =>
        "This meta-schema also defines keywords that have appeared in previous drafts in order to prevent incompatible extensions as they remain in common use.",
      "$dynamicAnchor" => "meta",
      "$vocabulary" => %{
        "https://json-schema.org/draft/2020-12/vocab/applicator" => true,
        "https://json-schema.org/draft/2020-12/vocab/content" => true,
        "https://json-schema.org/draft/2020-12/vocab/core" => true,
        "https://json-schema.org/draft/2020-12/vocab/format-annotation" => true,
        "https://json-schema.org/draft/2020-12/vocab/meta-data" => true,
        "https://json-schema.org/draft/2020-12/vocab/unevaluated" => true,
        "https://json-schema.org/draft/2020-12/vocab/validation" => true
      },
      "allOf" => [
        %{"$ref" => "meta/core"},
        %{"$ref" => "meta/applicator"},
        %{"$ref" => "meta/unevaluated"},
        %{"$ref" => "meta/validation"},
        %{"$ref" => "meta/meta-data"},
        %{"$ref" => "meta/format-annotation"},
        %{"$ref" => "meta/content"}
      ],
      "properties" => %{
        "$recursiveAnchor" => %{
          "$comment" => "\"$recursiveAnchor\" has been replaced by \"$dynamicAnchor\".",
          "$ref" => "meta/core#/$defs/anchorString",
          "deprecated" => true
        },
        "$recursiveRef" => %{
          "$comment" => "\"$recursiveRef\" has been replaced by \"$dynamicRef\".",
          "$ref" => "meta/core#/$defs/uriReferenceString",
          "deprecated" => true
        },
        "definitions" => %{
          "$comment" => "\"definitions\" has been replaced by \"$defs\".",
          "additionalProperties" => %{"$dynamicRef" => "#meta"},
          "default" => %{},
          "deprecated" => true,
          "type" => "object"
        },
        "dependencies" => %{
          "$comment" =>
            "\"dependencies\" has been split and replaced by \"dependentSchemas\" and \"dependentRequired\" in order to serve their differing semantics.",
          "additionalProperties" => %{
            "anyOf" => [
              %{"$dynamicRef" => "#meta"},
              %{"$ref" => "meta/validation#/$defs/stringArray"}
            ]
          },
          "default" => %{},
          "deprecated" => true,
          "type" => "object"
        }
      },
      "title" => "Core and Validation specifications meta-schema",
      "type" => ["object", "boolean"]
    }
  end
end
