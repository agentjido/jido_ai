defmodule JSV.Resolver.Embedded.Draft202012.Meta.Content do
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
      "$id" => "https://json-schema.org/draft/2020-12/meta/content",
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "properties" => %{
        "contentEncoding" => %{"type" => "string"},
        "contentMediaType" => %{"type" => "string"},
        "contentSchema" => %{"$dynamicRef" => "#meta"}
      },
      "title" => "Content vocabulary meta-schema",
      "type" => ["object", "boolean"]
    }
  end
end
