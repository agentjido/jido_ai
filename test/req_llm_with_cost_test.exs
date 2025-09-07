defmodule ReqLLM.WithCostTest do
  use ExUnit.Case, async: true

  describe "with_cost/1" do
    test "returns cost when usage metadata contains cost" do
      # Mock result with response containing usage data
      response = %Req.Response{
        status: 200,
        body: "Hello world",
        private: %{req_llm: %{usage: %{tokens: %{input: 10, output: 15}, cost: 0.00075}}}
      }

      result = ReqLLM.with_cost({:ok, response})
      assert {:ok, "Hello world", 0.00075} == result
    end

    test "returns nil cost when usage metadata has no cost" do
      response = %Req.Response{
        status: 200,
        body: "Hello world",
        private: %{req_llm: %{usage: %{tokens: %{input: 10, output: 15}}}}
      }

      result = ReqLLM.with_cost({:ok, response})
      assert {:ok, "Hello world", nil} == result
    end

    test "returns nil cost when usage metadata is nil" do
      response = %Req.Response{
        status: 200,
        body: "Hello world",
        private: %{req_llm: %{usage: nil}}
      }

      result = ReqLLM.with_cost({:ok, response})
      assert {:ok, "Hello world", nil} == result
    end

    test "returns nil cost for non-response results" do
      result = ReqLLM.with_cost({:ok, "Hello world"})
      assert {:ok, "Hello world", nil} == result
    end

    test "propagates errors" do
      error = %ReqLLM.Error.Invalid.Provider{}
      result = ReqLLM.with_cost({:error, error})
      assert {:error, error} == result
    end

    test "function exists and has correct arity" do
      assert function_exported?(ReqLLM, :with_cost, 1)
      assert function_exported?(ReqLLM, :generate_text, 3)
      assert function_exported?(ReqLLM, :generate_text!, 3)
    end
  end
end
