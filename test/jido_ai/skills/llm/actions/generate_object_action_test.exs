defmodule Jido.AI.Actions.LLM.GenerateObjectTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Actions.LLM.GenerateObject
  alias Jido.AI.TestSupport.FakeReqLLM

  @moduletag :unit
  @moduletag :capture_log

  setup :set_mimic_from_context
  setup :stub_req_llm

  defp stub_req_llm(context), do: FakeReqLLM.setup_stubs(context)

  describe "schema" do
    test "has required and optional fields" do
      assert GenerateObject.schema().fields[:prompt].meta.required == true
      assert GenerateObject.schema().fields[:object_schema].meta.required == true
      refute GenerateObject.schema().fields[:model].meta.required
      refute GenerateObject.schema().fields[:system_prompt].meta.required
      refute GenerateObject.schema().fields[:timeout].meta.required
    end

    test "has expected defaults" do
      assert GenerateObject.schema().fields[:max_tokens].value == 1024
      assert GenerateObject.schema().fields[:temperature].value == 0.7
    end
  end

  describe "run/2" do
    test "returns response on happy path with default model resolution" do
      schema = Zoi.object(%{name: Zoi.string()})

      assert {:ok, result} =
               GenerateObject.run(%{prompt: "Generate a person", object_schema: schema}, %{})

      assert result.model == Jido.AI.resolve_model(:fast)
      assert is_map(result.object)
      assert result.object[:name] == "stubbed"
      assert result.usage.total_tokens == result.usage.input_tokens + result.usage.output_tokens
    end

    test "returns validation error when prompt is missing" do
      schema = Zoi.object(%{name: Zoi.string()})
      assert {:error, _reason} = GenerateObject.run(%{object_schema: schema}, %{})
    end

    test "returns validation error when object_schema is missing" do
      assert {:error, _reason} = GenerateObject.run(%{prompt: "Generate a person"}, %{})
    end

    test "accepts NimbleOptions keyword list schema" do
      schema = [
        name: [type: :string, required: true],
        age: [type: :integer, required: true]
      ]

      assert {:ok, result} =
               GenerateObject.run(%{prompt: "Generate a person", object_schema: schema}, %{})

      assert is_map(result.object)
    end

    test "applies plugin defaults when fields are omitted" do
      schema = Zoi.object(%{name: Zoi.string()})

      context = %{
        provided_params: [:prompt, :object_schema],
        plugin_state: %{
          chat: %{
            default_model: :capable,
            default_system_prompt: "Return valid JSON",
            default_max_tokens: 321,
            default_temperature: 0.11
          }
        }
      }

      expect(ReqLLM.Generation, :generate_object, fn model, messages, req_schema, opts ->
        assert model == Jido.AI.resolve_model(:capable)
        assert req_schema == schema
        assert opts[:max_tokens] == 321
        assert opts[:temperature] == 0.11
        assert has_system_prompt?(messages, "Return valid JSON")

        {:ok,
         %{
           object: %{name: "alice"},
           usage: %{input_tokens: 5, output_tokens: 7}
         }}
      end)

      params = %{prompt: "Generate person data", object_schema: schema}
      assert {:ok, result} = GenerateObject.run(params, context)
      assert result.model == Jido.AI.resolve_model(:capable)
      assert result.object == %{name: "alice"}
    end

    test "explicit params override plugin defaults" do
      schema = Zoi.object(%{name: Zoi.string()})

      context = %{
        provided_params: [:prompt, :object_schema, :model, :system_prompt, :max_tokens, :temperature],
        plugin_state: %{
          chat: %{
            default_model: :fast,
            default_system_prompt: "Default",
            default_max_tokens: 777,
            default_temperature: 0.8
          }
        }
      }

      params = %{
        prompt: "Generate person data",
        object_schema: schema,
        model: "custom:model",
        system_prompt: "Explicit system prompt",
        max_tokens: 44,
        temperature: 0.2
      }

      expect(ReqLLM.Generation, :generate_object, fn model, messages, req_schema, opts ->
        assert model == "custom:model"
        assert req_schema == schema
        assert opts[:max_tokens] == 44
        assert opts[:temperature] == 0.2
        assert has_system_prompt?(messages, "Explicit system prompt")

        {:ok, %{object: %{name: "explicit"}, usage: %{input_tokens: 1, output_tokens: 2}}}
      end)

      assert {:ok, result} = GenerateObject.run(params, context)
      assert result.model == "custom:model"
      assert result.object == %{name: "explicit"}
    end

    test "sanitizes provider errors" do
      schema = Zoi.object(%{name: Zoi.string()})

      expect(ReqLLM.Generation, :generate_object, fn _model, _messages, _schema, _opts ->
        {:error, :timeout}
      end)

      params = %{prompt: "Generate person data", object_schema: schema}
      assert {:error, "Request timed out"} = GenerateObject.run(params, %{})
    end

    test "returns sanitized error on invalid model format" do
      schema = Zoi.object(%{name: Zoi.string()})
      params = %{prompt: "Generate person data", object_schema: schema, model: 123}
      assert {:error, "An error occurred"} = GenerateObject.run(params, %{})
    end
  end

  defp has_system_prompt?(messages, expected) do
    Enum.any?(messages, fn
      %{role: role, content: content} when role in [:system, "system"] ->
        content_to_string(content) == expected

      _ ->
        false
    end)
  end

  defp content_to_string(content) when is_binary(content), do: content
  defp content_to_string(content) when is_list(content), do: Jido.AI.Turn.extract_from_content(content)
  defp content_to_string(_), do: ""
end
