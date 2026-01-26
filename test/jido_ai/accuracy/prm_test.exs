defmodule Jido.AI.Accuracy.PrmTest do
  use ExUnit.Case

  @moduletag :capture_log

  describe "behavior implementation" do
    test "LLMPrm implements score_step/4 callback" do
      # Check that LLMPrm (which implements the behavior) has the function
      assert function_exported?(Jido.AI.Accuracy.Prms.LLMPrm, :score_step, 4)
    end

    test "LLMPrm implements score_trace/4 callback" do
      assert function_exported?(Jido.AI.Accuracy.Prms.LLMPrm, :score_trace, 4)
    end

    test "LLMPrm implements classify_step/4 callback" do
      assert function_exported?(Jido.AI.Accuracy.Prms.LLMPrm, :classify_step, 4)
    end

    test "LLMPrm implements supports_streaming?/0 callback" do
      assert function_exported?(Jido.AI.Accuracy.Prms.LLMPrm, :supports_streaming?, 0)
    end
  end

  describe "behavior documentation" do
    test "Prm module has documentation" do
      # Use Code.fetch_docs to get docs from compiled module
      {:docs_v1, _, :elixir, "text/markdown", %{"en" => doc}, _, _} =
        Code.fetch_docs(Jido.AI.Accuracy.Prm)

      assert is_binary(doc)
      assert String.contains?(doc, "score_step")
    end
  end
end
