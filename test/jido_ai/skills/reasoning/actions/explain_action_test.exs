defmodule Jido.AI.Actions.Reasoning.ExplainTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Actions.Reasoning.Explain
  alias Jido.AI.TestSupport.FakeReqLLM

  @moduletag :unit
  @moduletag :capture_log

  setup :set_mimic_from_context
  setup :stub_req_llm

  defp stub_req_llm(context), do: FakeReqLLM.setup_stubs(context)

  describe "schema" do
    test "defines required fields and defaults" do
      assert Explain.schema().fields[:topic].meta.required == true
      refute Explain.schema().fields[:model].meta.required
      assert Explain.schema().fields[:detail_level].value == :intermediate
      assert Explain.schema().fields[:include_examples].value == true
      assert Explain.schema().fields[:max_tokens].value == 2048
      assert Explain.schema().fields[:temperature].value == 0.5
    end
  end

  describe "run/2 happy path" do
    test "returns structured explanation payload" do
      assert {:ok, result} =
               Explain.run(%{topic: "Recursion", detail_level: :basic, include_examples: false}, %{})

      assert result.detail_level == :basic
      assert result.model == Jido.AI.resolve_model(:reasoning)
      assert result.result =~ "Stubbed response for: Explain: Recursion"
      assert_usage(result.usage)
    end

    test "accepts optional audience details" do
      params = %{
        topic: "Tail call optimization",
        detail_level: :advanced,
        audience: "Elixir developers"
      }

      assert {:ok, result} = Explain.run(params, %{})
      assert result.detail_level == :advanced
      assert result.result =~ "Target Audience: Elixir developers"
      assert_usage(result.usage)
    end
  end

  describe "validation and security" do
    test "returns error when topic is missing" do
      assert {:error, :topic_required} = Explain.run(%{}, %{})
    end

    test "returns error when topic is empty" do
      assert {:error, :topic_required} = Explain.run(%{topic: "   "}, %{})
    end

    test "rejects dangerous characters in topic" do
      assert {:error, {:dangerous_character, _char}} =
               Explain.run(%{topic: "Recursion" <> <<0>>, detail_level: :basic}, %{})
    end

    test "rejects dangerous characters in audience" do
      assert {:error, {:dangerous_character, _char}} =
               Explain.run(%{topic: "Recursion", audience: "developers" <> <<0>>}, %{})
    end
  end

  describe "schema-enforced errors via Jido.Exec" do
    test "rejects unsupported detail_level values" do
      assert {:error, _} =
               Jido.Exec.run(Explain, %{topic: "Recursion", detail_level: :novice}, %{})
    end
  end

  defp assert_usage(usage) do
    assert usage.input_tokens > 0
    assert usage.output_tokens > 0
    assert usage.total_tokens == usage.input_tokens + usage.output_tokens
  end
end
