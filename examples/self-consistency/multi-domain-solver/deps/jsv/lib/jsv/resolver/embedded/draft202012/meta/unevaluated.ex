defmodule JSV.Resolver.Embedded.Draft202012.Meta.Unevaluated do
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
      "$id" => "https://json-schema.org/draft/2020-12/meta/unevaluated",
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "properties" => %{
        "unevaluatedItems" => %{"$dynamicRef" => "#meta"},
        "unevaluatedProperties" => %{"$dynamicRef" => "#meta"}
      },
      "title" => "Unevaluated applicator vocabulary meta-schema",
      "type" => ["object", "boolean"]
    }
  end
end
