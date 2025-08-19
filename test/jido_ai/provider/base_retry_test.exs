defmodule Jido.AI.Provider.BaseRetryTest do
  use Jido.AI.TestSupport.HTTPCase

  alias Jido.AI.Error
  alias Jido.AI.Provider.{Base, OpenAI}
  alias Jido.AI.Test.Fixtures.ModelFixtures

  describe "retry logic for generate_object" do
    test "succeeds on first attempt when validation passes", %{test_name: test_name} do
      model = ModelFixtures.gpt4()
      schema = [name: [type: :string, required: true]]

      valid_response = %{
        "choices" => [
          %{
            "message" => %{
              "content" => ~s({"name": "John Doe"})
            }
          }
        ]
      }

      with_success(valid_response) do
        result = Base.default_generate_object(OpenAI, model, "Generate a person", schema)
        assert {:ok, %{"name" => "John Doe"}} = result
      end
    end

    test "retry prompt includes validation error feedback" do
      original_prompt = "Generate a person"
      schema = [name: [type: :string, required: true]]

      validation_errors = [
        %{field: "name", message: "is required"},
        %{field: "age", message: "must be an integer"}
      ]

      error = %Error.SchemaValidation{validation_errors: validation_errors}

      retry_prompt = Base.build_retry_prompt(original_prompt, schema, error)

      assert retry_prompt =~ original_prompt
      assert retry_prompt =~ "VALIDATION ERROR"
      assert retry_prompt =~ "name: is required"
      assert retry_prompt =~ "age: must be an integer"
      assert retry_prompt =~ "valid JSON"
    end
  end
end
