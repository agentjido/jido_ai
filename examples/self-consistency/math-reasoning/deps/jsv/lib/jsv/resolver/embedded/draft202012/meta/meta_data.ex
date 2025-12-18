defmodule JSV.Resolver.Embedded.Draft202012.Meta.MetaData do
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
      "$id" => "https://json-schema.org/draft/2020-12/meta/meta-data",
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "properties" => %{
        "default" => true,
        "deprecated" => %{"default" => false, "type" => "boolean"},
        "description" => %{"type" => "string"},
        "examples" => %{"items" => true, "type" => "array"},
        "readOnly" => %{"default" => false, "type" => "boolean"},
        "title" => %{"type" => "string"},
        "writeOnly" => %{"default" => false, "type" => "boolean"}
      },
      "title" => "Meta-data vocabulary meta-schema",
      "type" => ["object", "boolean"]
    }
  end
end
