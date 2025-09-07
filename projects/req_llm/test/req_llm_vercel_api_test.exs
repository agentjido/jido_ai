defmodule ReqLLMVercelAPITest do
  use ExUnit.Case, async: true
  doctest ReqLLM

  describe "Vercel AI SDK compatibility methods" do
    test "tool/1 delegates to Utils.tool/1" do
      opts = [
        name: "test_tool",
        description: "Test tool",
        callback: fn _args -> {:ok, "result"} end
      ]

      tool = ReqLLM.tool(opts)

      assert tool.name == "test_tool"
      assert tool.description == "Test tool"
      assert is_function(tool.callback, 1)
    end

    test "json_schema/2 delegates to Utils.json_schema/2" do
      schema = [
        name: [type: :string, required: true, doc: "Name"],
        value: [type: :integer, doc: "Value"]
      ]

      json_schema = ReqLLM.json_schema(schema)

      assert json_schema["type"] == "object"
      assert json_schema["properties"]["name"]["type"] == "string"
      assert json_schema["properties"]["value"]["type"] == "integer"
      assert json_schema["required"] == ["name"]
    end

    test "json_schema/1 works with default options" do
      schema = [name: [type: :string, required: true]]
      
      json_schema = ReqLLM.json_schema(schema)
      
      assert json_schema["type"] == "object"
      assert json_schema["properties"]["name"]["type"] == "string"
      assert json_schema["required"] == ["name"]
    end

    test "cosine_similarity/2 delegates to Utils.cosine_similarity/2" do
      embedding_a = [1.0, 0.0, 0.0]
      embedding_b = [1.0, 0.0, 0.0]
      
      similarity = ReqLLM.cosine_similarity(embedding_a, embedding_b)
      assert_in_delta similarity, 1.0, 0.0001
    end

    test "cosine_similarity/2 calculates real similarity" do
      embedding_a = [0.8, 0.6]
      embedding_b = [0.6, 0.8]
      
      similarity = ReqLLM.cosine_similarity(embedding_a, embedding_b)
      # Expected: approximately 0.96
      assert similarity > 0.9
      assert similarity < 1.0
    end
  end

  describe "facade API integration" do
    test "all Vercel methods are available at module level" do
      # Test that the facade exposes the methods
      assert function_exported?(ReqLLM, :tool, 1)
      assert function_exported?(ReqLLM, :json_schema, 1)
      assert function_exported?(ReqLLM, :json_schema, 2)
      assert function_exported?(ReqLLM, :cosine_similarity, 2)
    end
  end
end
