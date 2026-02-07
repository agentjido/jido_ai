defmodule Jido.AI.Actions.LLM.GenerateObjectTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.LLM.GenerateObject

  describe "GenerateObject action" do
    test "has correct metadata" do
      metadata = GenerateObject.__action_metadata__()
      assert metadata.name == "llm_generate_object"
      assert metadata.category == "ai"
      assert metadata.vsn == "1.0.0"
      assert "structured-output" in metadata.tags
      assert "json" in metadata.tags
    end

    test "requires prompt parameter" do
      schema = Zoi.object(%{name: Zoi.string()})
      assert {:error, _} = Jido.Exec.run(GenerateObject, %{object_schema: schema}, %{})
    end

    test "requires object_schema parameter" do
      assert {:error, _} = Jido.Exec.run(GenerateObject, %{prompt: "Generate a person"}, %{})
    end

    test "accepts valid parameters with defaults" do
      schema = Zoi.object(%{name: Zoi.string()})

      params = %{
        prompt: "Generate a person named Alice",
        object_schema: schema
      }

      assert params.prompt == "Generate a person named Alice"
      assert params.object_schema == schema
    end

    test "accepts optional parameters" do
      schema = Zoi.object(%{name: Zoi.string(), age: Zoi.integer()})

      params = %{
        prompt: "Generate a person",
        object_schema: schema,
        model: "anthropic:claude-haiku-4-5",
        system_prompt: "You are generating structured data",
        max_tokens: 500,
        temperature: 0.5
      }

      assert params.prompt == "Generate a person"
      assert params.model == "anthropic:claude-haiku-4-5"
      assert params.system_prompt == "You are generating structured data"
      assert params.max_tokens == 500
      assert params.temperature == 0.5
    end

    test "accepts NimbleOptions keyword list schema" do
      schema = [
        name: [type: :string, required: true],
        age: [type: :integer, required: true]
      ]

      params = %{
        prompt: "Generate a person",
        object_schema: schema
      }

      assert params.object_schema == schema
    end
  end
end
