defmodule JSV.Resolver.Embedded.Draft202012.Meta.FormatAnnotation do
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
      "$dynamicAnchor" => "meta",
      "$id" => "https://json-schema.org/draft/2020-12/meta/format-annotation",
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "properties" => %{"format" => %{"type" => "string"}},
      "title" => "Format vocabulary meta-schema for annotation results",
      "type" => ["object", "boolean"]
    }
  end
end
