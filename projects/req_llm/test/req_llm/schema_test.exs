defmodule ReqLLM.SchemaTest do
  use ExUnit.Case, async: true

  alias ReqLLM.Schema
  alias ReqLLM.Tool

  describe "compile/1" do
    test "compiles valid keyword schemas" do
      schema = [name: [type: :string, required: true], age: [type: :pos_integer, default: 0]]
      assert {:ok, compiled} = Schema.compile(schema)
      assert %NimbleOptions{} = compiled
    end

    test "compiles empty schema" do
      assert {:ok, compiled} = Schema.compile([])
      assert %NimbleOptions{} = compiled
    end

    test "returns error for invalid input types" do
      assert {:error, %ReqLLM.Error.Invalid.Parameter{}} = Schema.compile("invalid")
      assert {:error, %ReqLLM.Error.Invalid.Parameter{}} = Schema.compile(%{})
      assert {:error, %ReqLLM.Error.Invalid.Parameter{}} = Schema.compile(123)
    end

    test "returns error for malformed schema" do
      assert {:error, %ReqLLM.Error.Validation.Error{}} = Schema.compile([:invalid])
      assert {:error, %ReqLLM.Error.Validation.Error{}} = Schema.compile(name: :invalid)
    end
  end

  describe "to_json/1" do
    test "converts empty schema" do
      assert Schema.to_json([]) == %{"type" => "object", "properties" => %{}}
    end

    test "converts simple schema with required fields" do
      schema = [name: [type: :string, required: true, doc: "User name"]]

      result = Schema.to_json(schema)

      assert result["type"] == "object"
      assert result["properties"]["name"] == %{"type" => "string", "description" => "User name"}
      assert result["required"] == ["name"]
    end

    test "converts complex schema" do
      schema = [
        name: [type: :string, required: true, doc: "User name"],
        age: [type: :pos_integer, doc: "User age"],
        tags: [type: {:list, :string}, doc: "User tags"],
        active: [type: :boolean, required: true]
      ]

      result = Schema.to_json(schema)

      assert result["type"] == "object"
      assert result["properties"]["name"]["type"] == "string"
      assert result["properties"]["age"]["type"] == "integer"
      assert result["properties"]["age"]["minimum"] == 1
      assert result["properties"]["tags"]["type"] == "array"
      assert result["properties"]["tags"]["items"]["type"] == "string"
      assert result["properties"]["active"]["type"] == "boolean"
      assert Enum.sort(result["required"]) == ["active", "name"]
    end

    test "handles schema without required fields" do
      schema = [name: [type: :string, doc: "User name"], age: [type: :integer]]

      result = Schema.to_json(schema)

      refute Map.has_key?(result, "required")
    end

    test "reverses field order for required fields" do
      schema = [
        c: [type: :string, required: true],
        a: [type: :string, required: true],
        b: [type: :string, required: true]
      ]

      result = Schema.to_json(schema)

      assert result["required"] == ["c", "a", "b"]
    end
  end

  describe "nimble_type_to_json_schema/2" do
    test "converts basic types" do
      assert Schema.nimble_type_to_json_schema(:string, []) == %{"type" => "string"}
      assert Schema.nimble_type_to_json_schema(:integer, []) == %{"type" => "integer"}
      assert Schema.nimble_type_to_json_schema(:boolean, []) == %{"type" => "boolean"}
      assert Schema.nimble_type_to_json_schema(:float, []) == %{"type" => "number"}
      assert Schema.nimble_type_to_json_schema(:number, []) == %{"type" => "number"}
      assert Schema.nimble_type_to_json_schema(:map, []) == %{"type" => "object"}
      assert Schema.nimble_type_to_json_schema(:atom, []) == %{"type" => "string"}
    end

    test "converts constrained types" do
      assert Schema.nimble_type_to_json_schema(:pos_integer, []) == %{
               "type" => "integer",
               "minimum" => 1
             }
    end

    test "converts list types" do
      assert Schema.nimble_type_to_json_schema({:list, :string}, []) == %{
               "type" => "array",
               "items" => %{"type" => "string"}
             }

      assert Schema.nimble_type_to_json_schema({:list, :integer}, []) == %{
               "type" => "array",
               "items" => %{"type" => "integer"}
             }

      assert Schema.nimble_type_to_json_schema({:list, :boolean}, []) == %{
               "type" => "array",
               "items" => %{"type" => "boolean"}
             }

      assert Schema.nimble_type_to_json_schema({:list, :float}, []) == %{
               "type" => "array",
               "items" => %{"type" => "number"}
             }

      assert Schema.nimble_type_to_json_schema({:list, :number}, []) == %{
               "type" => "array",
               "items" => %{"type" => "number"}
             }

      assert Schema.nimble_type_to_json_schema({:list, :pos_integer}, []) == %{
               "type" => "array",
               "items" => %{"type" => "integer", "minimum" => 1}
             }
    end

    test "converts nested list types recursively" do
      assert Schema.nimble_type_to_json_schema({:list, :atom}, []) == %{
               "type" => "array",
               "items" => %{"type" => "string"}
             }
    end

    test "converts map types" do
      assert Schema.nimble_type_to_json_schema({:map, :any}, []) == %{"type" => "object"}
      assert Schema.nimble_type_to_json_schema(:keyword_list, []) == %{"type" => "object"}
    end

    test "fallback for unknown types" do
      assert Schema.nimble_type_to_json_schema(:custom_type, []) == %{"type" => "string"}
      assert Schema.nimble_type_to_json_schema({:custom, :type}, []) == %{"type" => "string"}
    end

    test "adds description from doc option" do
      result = Schema.nimble_type_to_json_schema(:string, doc: "A text field")
      assert result == %{"type" => "string", "description" => "A text field"}

      result = Schema.nimble_type_to_json_schema({:list, :string}, doc: "List of strings")

      assert result == %{
               "type" => "array",
               "items" => %{"type" => "string"},
               "description" => "List of strings"
             }
    end

    test "ignores nil doc option" do
      result = Schema.nimble_type_to_json_schema(:string, doc: nil)
      assert result == %{"type" => "string"}

      result = Schema.nimble_type_to_json_schema(:string, [])
      assert result == %{"type" => "string"}
    end
  end

  describe "to_anthropic/1" do
    setup do
      tool = %Tool{
        name: "search",
        description: "Search for items",
        parameter_schema: [
          query: [type: :string, required: true, doc: "Search query"],
          limit: [type: :pos_integer, doc: "Maximum results"]
        ],
        callback: fn _ -> {:ok, %{}} end
      }

      {:ok, tool: tool}
    end

    test "formats tool with parameters", %{tool: tool} do
      result = Schema.to_anthropic(tool)

      assert result == %{
               "name" => "search",
               "description" => "Search for items",
               "input_schema" => %{
                 "type" => "object",
                 "properties" => %{
                   "query" => %{"type" => "string", "description" => "Search query"},
                   "limit" => %{
                     "type" => "integer",
                     "minimum" => 1,
                     "description" => "Maximum results"
                   }
                 },
                 "required" => ["query"]
               }
             }
    end

    test "formats tool without parameters" do
      tool = %Tool{
        name: "ping",
        description: "Health check",
        parameter_schema: [],
        callback: fn _ -> {:ok, %{}} end
      }

      result = Schema.to_anthropic(tool)

      assert result == %{
               "name" => "ping",
               "description" => "Health check",
               "input_schema" => %{
                 "type" => "object",
                 "properties" => %{}
               }
             }
    end

    test "formats tool with complex parameter types" do
      tool = %Tool{
        name: "complex_tool",
        description: "Tool with various parameter types",
        parameter_schema: [
          tags: [type: {:list, :string}, required: true, doc: "List of tags"],
          enabled: [type: :boolean, doc: "Whether enabled"],
          config: [type: :map, doc: "Configuration object"]
        ],
        callback: fn _ -> {:ok, %{}} end
      }

      result = Schema.to_anthropic(tool)

      assert result["input_schema"]["properties"]["tags"]["type"] == "array"
      assert result["input_schema"]["properties"]["tags"]["items"]["type"] == "string"
      assert result["input_schema"]["properties"]["enabled"]["type"] == "boolean"
      assert result["input_schema"]["properties"]["config"]["type"] == "object"
      assert result["input_schema"]["required"] == ["tags"]
    end
  end
end
