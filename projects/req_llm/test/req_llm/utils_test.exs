defmodule ReqLLM.UtilsTest do
  use ExUnit.Case, async: true
  doctest ReqLLM.Utils

  alias ReqLLM.Utils

  describe "tool/1" do
    test "creates a Tool struct with valid parameters" do
      opts = [
        name: "get_weather",
        description: "Get current weather",
        parameters: [
          location: [type: :string, required: true, doc: "City name"]
        ],
        callback: fn _args -> {:ok, "sunny"} end
      ]

      tool = Utils.tool(opts)

      assert tool.name == "get_weather"
      assert tool.description == "Get current weather"
      assert is_function(tool.callback, 1)
    end

    test "creates a Tool struct with MFA callback" do
      opts = [
        name: "test_tool",
        description: "Test tool",
        callback: {String, :upcase}
      ]

      tool = Utils.tool(opts)
      assert tool.callback == {String, :upcase}
    end
  end

  describe "json_schema/2" do
    test "creates basic JSON schema from NimbleOptions schema" do
      schema = [
        name: [type: :string, required: true, doc: "User name"],
        age: [type: :integer, doc: "User age"]
      ]

      json_schema = Utils.json_schema(schema)

      assert json_schema["type"] == "object"
      assert json_schema["properties"]["name"]["type"] == "string"
      assert json_schema["properties"]["name"]["description"] == "User name"
      assert json_schema["properties"]["age"]["type"] == "integer"
      assert json_schema["required"] == ["name"]
    end

    test "creates JSON schema with custom validation" do
      schema = [email: [type: :string, required: true]]
      
      validator = fn value ->
        if String.contains?(value["email"], "@") do
          {:ok, value}
        else
          {:error, "Invalid email format"}
        end
      end

      json_schema = Utils.json_schema(schema, validate: validator)

      assert json_schema["type"] == "object"
      assert is_function(json_schema[:validate], 1)
    end

    test "handles empty schema" do
      json_schema = Utils.json_schema([])
      
      assert json_schema["type"] == "object"
      assert json_schema["properties"] == %{}
      refute Map.has_key?(json_schema, "required")
    end
  end

  describe "cosine_similarity/2" do
    test "returns 1.0 for identical vectors" do
      embedding_a = [1.0, 0.0, 0.0]
      embedding_b = [1.0, 0.0, 0.0]
      
      similarity = Utils.cosine_similarity(embedding_a, embedding_b)
      assert_in_delta similarity, 1.0, 0.0001
    end

    test "returns 0.0 for orthogonal vectors" do
      embedding_a = [1.0, 0.0]
      embedding_b = [0.0, 1.0]
      
      similarity = Utils.cosine_similarity(embedding_a, embedding_b)
      assert_in_delta similarity, 0.0, 0.0001
    end

    test "returns -1.0 for opposite vectors" do
      embedding_a = [1.0, 0.0]
      embedding_b = [-1.0, 0.0]
      
      similarity = Utils.cosine_similarity(embedding_a, embedding_b)
      assert_in_delta similarity, -1.0, 0.0001
    end

    test "calculates similarity for realistic vectors" do
      embedding_a = [0.5, 0.8, 0.3]
      embedding_b = [0.6, 0.7, 0.4]
      
      similarity = Utils.cosine_similarity(embedding_a, embedding_b)
      # Expected: approximately 0.9487
      assert similarity > 0.9
      assert similarity < 1.0
    end

    test "handles zero vectors" do
      embedding_a = [0.0, 0.0, 0.0]
      embedding_b = [1.0, 0.0, 0.0]
      
      similarity = Utils.cosine_similarity(embedding_a, embedding_b)
      assert similarity == 0.0
    end

    test "raises error for different length vectors" do
      embedding_a = [1.0, 0.0]
      embedding_b = [1.0, 0.0, 0.0]
      
      assert_raise ArgumentError, "Embedding vectors must have the same length", fn ->
        Utils.cosine_similarity(embedding_a, embedding_b)
      end
    end

    test "handles empty vectors" do
      embedding_a = []
      embedding_b = []
      
      similarity = Utils.cosine_similarity(embedding_a, embedding_b)
      assert similarity == 0.0
    end
  end
end
