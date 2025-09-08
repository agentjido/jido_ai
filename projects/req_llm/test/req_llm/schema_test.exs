defmodule ReqLLM.SchemaTest do
  use ExUnit.Case, async: true

  alias ReqLLM.Schema
  alias ReqLLM.Tool

  describe "Schema" do
    test "compiles keyword schemas" do
      schema = [name: [type: :string, required: true], age: [type: :pos_integer, default: 0]]
      assert {:ok, compiled} = Schema.compile(schema)
      assert %NimbleOptions{} = compiled

      assert {:error, _} = Schema.compile("invalid")
    end

    test "converts to JSON Schema" do
      assert Schema.to_json([]) == %{"type" => "object", "properties" => %{}}

      schema = [
        name: [type: :string, required: true, doc: "User name"],
        tags: [type: {:list, :string}, doc: "User tags"]
      ]

      result = Schema.to_json(schema)
      assert result["type"] == "object"
      assert result["properties"]["name"]["type"] == "string"
      assert result["properties"]["tags"]["type"] == "array"
      assert result["properties"]["tags"]["items"]["type"] == "string"
      assert result["required"] == ["name"]
    end

    # Removed OpenAI-specific test since we're focusing on Anthropic only

    test "converts nimble types to JSON Schema" do
      assert Schema.nimble_type_to_json_schema(:string, []) == %{"type" => "string"}
      assert Schema.nimble_type_to_json_schema(:integer, []) == %{"type" => "integer"}
      assert Schema.nimble_type_to_json_schema(:boolean, []) == %{"type" => "boolean"}

      assert Schema.nimble_type_to_json_schema(:pos_integer, []) == %{
               "type" => "integer",
               "minimum" => 1
             }

      assert Schema.nimble_type_to_json_schema({:list, :string}, []) == %{
               "type" => "array",
               "items" => %{"type" => "string"}
             }

      result = Schema.nimble_type_to_json_schema(:string, doc: "A text field")
      assert result == %{"type" => "string", "description" => "A text field"}
    end

    # Removed OpenAI-specific test since we're focusing on Anthropic only

    test "formats tools for Anthropic" do
      tool = %Tool{
        name: "search",
        description: "Search for items",
        parameter_schema: [query: [type: :string, required: true, doc: "Search query"]],
        callback: fn _ -> {:ok, %{}} end
      }

      result = Schema.to_anthropic(tool)

      assert result == %{
               "name" => "search",
               "description" => "Search for items",
               "input_schema" => %{
                 "type" => "object",
                 "properties" => %{
                   "query" => %{"type" => "string", "description" => "Search query"}
                 },
                 "required" => ["query"]
               }
             }
    end
  end
end
