defmodule Jido.AI.Actions.Reasoning.InferTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Actions.Reasoning.Infer
  alias Jido.AI.TestSupport.FakeReqLLM

  @moduletag :unit
  @moduletag :capture_log

  setup :set_mimic_from_context
  setup :stub_req_llm

  defp stub_req_llm(context), do: FakeReqLLM.setup_stubs(context)

  describe "schema" do
    test "defines required fields and defaults" do
      assert Infer.schema().fields[:premises].meta.required == true
      assert Infer.schema().fields[:question].meta.required == true
      refute Infer.schema().fields[:model].meta.required
      refute Infer.schema().fields[:context].meta.required
      assert Infer.schema().fields[:max_tokens].value == 2048
      assert Infer.schema().fields[:temperature].value == 0.3
    end
  end

  describe "run/2 happy path" do
    test "returns structured inference payload" do
      params = %{
        premises: "All cats are mammals. Fluffy is a cat.",
        question: "Is Fluffy a mammal?"
      }

      assert {:ok, result} = Infer.run(params, %{})

      assert result.model == Jido.AI.resolve_model(:reasoning)
      assert result.result =~ "Premises:"
      assert result.reasoning == result.result
      assert Map.has_key?(result, :confidence)
      assert_usage(result.usage)
    end

    test "extracts the requested confidence value" do
      expect(ReqLLM.Generation, :generate_text, fn _model, _messages, _opts ->
        {:ok,
         %{
           message: %{content: "The conclusion follows.\nCONFIDENCE: 0.87"},
           usage: %{input_tokens: 3, output_tokens: 4}
         }}
      end)

      assert {:ok, result} =
               Infer.run(
                 %{premises: "All cats are mammals.", question: "Are cats mammals?"},
                 %{}
               )

      assert result.confidence == 0.87
    end

    test "includes optional context in inference prompt" do
      params = %{
        premises: "If a service is down, alerts are triggered.",
        question: "What can we infer if alerts fired?",
        context: "Alerting can also fire during scheduled drills."
      }

      assert {:ok, result} = Infer.run(params, %{})
      assert result.result =~ "Additional Context:"
      assert_usage(result.usage)
    end
  end

  describe "validation and security" do
    test "returns an error for an unsupported model value" do
      assert {:error, :invalid_model_format} =
               Infer.run(%{model: [:invalid], premises: "A", question: "B"}, %{})
    end

    test "returns error when premises are missing" do
      assert {:error, :premises_and_question_required} = Infer.run(%{question: "Test"}, %{})
    end

    test "returns error when question is missing" do
      assert {:error, :premises_and_question_required} = Infer.run(%{premises: "Test"}, %{})
    end

    test "rejects dangerous characters in premises" do
      assert {:error, {:dangerous_character, _char}} =
               Infer.run(%{premises: "All cats" <> <<1>>, question: "Is Fluffy a cat?"}, %{})
    end

    test "rejects dangerous characters in context" do
      params = %{
        premises: "All cats are mammals",
        question: "Is Fluffy a mammal?",
        context: "Consider" <> <<0>> <> "other possibilities"
      }

      assert {:error, {:dangerous_character, _char}} = Infer.run(params, %{})
    end
  end

  describe "schema-enforced errors via Jido.Exec" do
    test "rejects invalid context type" do
      params = %{
        premises: "All cats are mammals",
        question: "Is Fluffy a mammal?",
        context: 123
      }

      assert {:error, _} = Jido.Exec.run(Infer, params, %{})
    end
  end

  defp assert_usage(usage) do
    assert usage.input_tokens > 0
    assert usage.output_tokens > 0
    assert usage.total_tokens == usage.input_tokens + usage.output_tokens
  end
end
