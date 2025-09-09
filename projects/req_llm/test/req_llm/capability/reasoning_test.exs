defmodule ReqLLM.Capability.ReasoningTest do
  @moduledoc """
  Unit tests for ReqLLM.Capability.Reasoning capability verification.

  Tests the Reasoning capability module's interface compliance and reasoning-specific behaviors
  including reasoning token detection, content extraction, and step-by-step pattern matching.
  """

  use ReqLLM.Test.CapabilityCase

  alias ReqLLM.Capability.Reasoning



  describe "advertised?/1" do
    test "returns true when model has reasoning capability" do
      model = test_model_with_capabilities([:reasoning])
      assert Reasoning.advertised?(model) == true
    end

    test "returns false when model lacks reasoning capability" do
      model = test_model_with_capabilities([])
      assert Reasoning.advertised?(model) == false
    end

    test "returns false when capabilities are nil" do
      model = test_model("openai", "gpt-4", capabilities: nil)
      assert Reasoning.advertised?(model) == false
    end

    test "handles different capability configurations" do
      test_cases = [
        {%{reasoning?: true}, true},
        {%{reasoning?: false}, false},
        {%{other_capability?: true}, false},
        {%{}, false}
      ]

      for {capabilities, expected} <- test_cases do
        model = test_model("openai", "gpt-4", capabilities: capabilities)
        assert Reasoning.advertised?(model) == expected,
               "Expected advertised?(#{inspect(capabilities)}) to be #{expected}"
      end
    end
  end

  describe "verify/2" do
    test "successful verification with reasoning tokens" do
      model = test_model("openai", "o1-preview")
      content = "Let me think step by step:\n1. Fill the 5-gallon jug\n2. Pour into 3-gallon jug"
      
      # Mock structured response with reasoning tokens
      mock_response = %Req.Response{
        status: 200,
        body: content,
        private: %{
          req_llm: %{
            usage: %{
              tokens: %{
                reasoning: 1250
              }
            }
          }
        }
      }

      Mimic.stub(ReqLLM, :generate_text, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      result = Reasoning.verify(model, [])

      assert {:ok, response_data} = result
      assert response_data.model_id == "openai:o1-preview"
      assert response_data.content_length == String.length(content)
      assert response_data.reasoning_length == 1250
      assert response_data.has_reasoning_tokens == true
      assert String.contains?(response_data.content_preview, "Let me think")
      # The reasoning extraction extracts the numbered steps part
      assert String.contains?(response_data.reasoning_preview, "Fill the 5-gallon")
    end

    test "successful verification without reasoning tokens" do
      model = test_model("openai", "gpt-4")
      content = "To solve this puzzle: Fill 5-gallon jug, pour into 3-gallon jug"
      
      # Mock structured response without reasoning tokens
      mock_response = %Req.Response{
        status: 200,
        body: content,
        private: %{
          req_llm: %{
            usage: %{
              tokens: %{
                input: 100,
                output: 50
              }
            }
          }
        }
      }

      Mimic.stub(ReqLLM, :generate_text, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      result = Reasoning.verify(model, [])

      assert {:ok, response_data} = result
      assert response_data.model_id == "openai:gpt-4"
      assert response_data.content_length == String.length(content)
      assert response_data.reasoning_length == 0
      assert response_data.has_reasoning_tokens == false
      assert response_data.reasoning_preview == nil
      assert String.contains?(response_data.warning, "No reasoning tokens detected")
    end

    test "handles responses without reasoning tokens" do
      no_tokens_cases = [
        {"structured without reasoning tokens", %{req_llm: %{usage: %{tokens: %{input: 50, output: 30}}}}},
        {"no req_llm metadata", %{some_other_field: "value"}}
      ]
      
      for {description, private_data} <- no_tokens_cases do
        model = test_model("anthropic", "claude-3-sonnet")
        content = "Here's my approach: 1. Use the 5-gallon jug 2. Transfer to 3-gallon"
        
        mock_response = %Req.Response{
          status: 200,
          body: content,
          private: private_data
        }

        Mimic.stub(ReqLLM, :generate_text, fn _model, _prompt, _opts ->
          {:ok, mock_response}
        end)

        result = Reasoning.verify(model, [])

        assert {:ok, response_data} = result, "Failed for #{description}"
        assert response_data.model_id == "anthropic:claude-3-sonnet"
        assert response_data.content_length == String.length(content)
        assert response_data.reasoning_length == 0
        assert response_data.has_reasoning_tokens == false
        assert String.contains?(response_data.warning, "No reasoning tokens detected")
      end
    end



    test "handles error cases appropriately" do
      model = test_model("openai", "gpt-4")

      # Test empty content with structured response
      Mimic.stub(ReqLLM, :generate_text, fn _model, _prompt, _opts ->
        {:ok, %Req.Response{body: "", private: %{req_llm: %{usage: %{tokens: %{}}}}}}
      end)
      
      result = Reasoning.verify(model, [])
      assert {:error, "Empty content response"} = result

      # Test whitespace-only content
      Mimic.stub(ReqLLM, :generate_text, fn _model, _prompt, _opts ->
        {:ok, %Req.Response{body: "   \n\t   ", private: %{req_llm: %{usage: %{tokens: %{}}}}}}
      end)
      
      result = Reasoning.verify(model, [])
      assert {:error, "Empty content response"} = result

      # Test empty plain text response (no private field)
      Mimic.stub(ReqLLM, :generate_text, fn _model, _prompt, _opts ->
        {:ok, %Req.Response{body: ""}}
      end)
      
      result = Reasoning.verify(model, [])
      # This will match the first pattern since private can be nil, but content is empty
      assert {:error, "Empty content response"} = result

      # Test API error
      Mimic.stub(ReqLLM, :generate_text, fn _model, _prompt, _opts ->
        {:error, "Network timeout"}
      end)
      
      result = Reasoning.verify(model, [])
      assert {:error, "Network timeout"} = result
    end
  end

  describe "reasoning snippet extraction" do
    test "extracts step-by-step reasoning patterns" do
      test_cases = [
        {"Step format", "Let me solve this step by step:\n1. First approach\n2. Then consider", "First approach"},
        {"Numbered list", "Here's the solution:\n1. Fill 5-gallon jug\n2. Pour into 3-gallon", "Fill 5-gallon jug"},
        {"Bullet points", "Solution approach:\n* Fill the larger jug\n* Transfer to smaller", "Fill the larger jug"},
        {"Dashes", "My reasoning:\n- Start with empty jugs\n- Fill the 5-gallon first", "Start with empty jugs"}
      ]

      model = test_model("openai", "o1-preview")

      for {description, content, expected_snippet_part} <- test_cases do
        mock_response = %Req.Response{
          body: content,
          private: %{req_llm: %{usage: %{tokens: %{reasoning: 100}}}}
        }

        Mimic.stub(ReqLLM, :generate_text, fn _model, _prompt, _opts ->
          {:ok, mock_response}
        end)

        result = Reasoning.verify(model, [])

        assert {:ok, response_data} = result, "Failed for #{description}"
        assert response_data.has_reasoning_tokens == true
        assert String.contains?(response_data.reasoning_preview, expected_snippet_part),
               "Reasoning preview '#{response_data.reasoning_preview}' doesn't contain expected text '#{expected_snippet_part}' for #{description}"
      end
    end

    test "extracts explanation sections" do
      test_cases = [
        {"Explicit reasoning", "My reasoning: This requires careful planning", "This requires careful planning"},
        {"Explanation section", "Explanation:\nWe need to measure exactly 4 gallons", "We need to measure exactly 4 gallons"},
        {"Here's how pattern", "Here's how I would solve this problem", "I would solve this problem"},
        {"Here's why pattern", "Here's why this works: The math checks out", "this works: The math checks out"},
        {"First approach", "First, let's understand the problem constraints", "let's understand the problem constraints"}
      ]

      model = test_model("openai", "o1-preview")

      for {description, content, expected_snippet_start} <- test_cases do
        mock_response = %Req.Response{
          body: content,
          private: %{req_llm: %{usage: %{tokens: %{reasoning: 50}}}}
        }

        Mimic.stub(ReqLLM, :generate_text, fn _model, _prompt, _opts ->
          {:ok, mock_response}
        end)

        result = Reasoning.verify(model, [])

        assert {:ok, response_data} = result, "Failed for #{description}"
        assert response_data.has_reasoning_tokens == true
        assert String.contains?(response_data.reasoning_preview, String.slice(expected_snippet_start, 0, 15)),
               "Reasoning preview doesn't contain expected text for #{description}"
      end
    end

    test "fallback reasoning extraction" do
      model = test_model("openai", "o1-preview")
      content = "This is a complex problem that requires multiple steps to solve properly."
      
      mock_response = %Req.Response{
        body: content,
        private: %{req_llm: %{usage: %{tokens: %{reasoning: 75}}}}
      }

      Mimic.stub(ReqLLM, :generate_text, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      result = Reasoning.verify(model, [])

      assert {:ok, response_data} = result
      assert response_data.has_reasoning_tokens == true
      # Should fallback to content preview (cleaned up)
      assert String.contains?(response_data.reasoning_preview, "This is a complex problem")
      assert String.length(response_data.reasoning_preview) <= 100
    end
  end

  describe "content preview handling" do
    test "truncates long content correctly" do
      model = test_model("openai", "gpt-4")
      long_content = String.duplicate("This is a very long reasoning explanation. ", 10)
      
      mock_response = %Req.Response{
        body: long_content,
        private: %{req_llm: %{usage: %{tokens: %{}}}}
      }

      Mimic.stub(ReqLLM, :generate_text, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      result = Reasoning.verify(model, [])

      assert {:ok, response_data} = result
      assert response_data.content_length == String.length(long_content)
      assert String.length(response_data.content_preview) == 100
      assert String.starts_with?(response_data.content_preview, "This is a very long")
    end

    test "handles unicode content properly" do
      model = test_model("openai", "gpt-4")
      unicode_content = "Reasoning: 数学的解法 🧮 Step 1: 水の移動 💧"
      
      mock_response = %Req.Response{
        body: unicode_content,
        private: %{req_llm: %{usage: %{tokens: %{}}}}
      }

      Mimic.stub(ReqLLM, :generate_text, fn _model, _prompt, _opts ->
        {:ok, mock_response}
      end)

      result = Reasoning.verify(model, [])

      assert {:ok, response_data} = result
      assert response_data.content_preview == unicode_content
      assert response_data.content_length == String.length(unicode_content)
    end
  end

  timeout_tests(Reasoning, :generate_text)
  model_id_tests(Reasoning, :generate_text)
  behaviour_tests(Reasoning)

  describe "verify/2 result format" do
    test "returns proper reasoning result structure" do
      model = test_model("openai", "gpt-4")

      # Test success format
      Mimic.stub(ReqLLM, :generate_text, fn _model, _prompt, _opts ->
        {:ok, %Req.Response{body: "Test reasoning", private: %{req_llm: %{usage: %{tokens: %{}}}}}}
      end)

      result = Reasoning.verify(model, [])
      assert {:ok, data} = result
      assert_reasoning_result(data)

      # Test error format
      Mimic.stub(ReqLLM, :generate_text, fn _model, _prompt, _opts ->
        {:error, "API error"}
      end)

      result = Reasoning.verify(model, [])
      assert_capability_result(result, :failed, :reasoning)
    end

    test "uses correct reasoning prompt" do
      model = test_model("openai", "gpt-4")

      Mimic.stub(ReqLLM, :generate_text, fn _model, prompt, _opts ->
        # Verify the reasoning prompt contains jug problem
        assert String.contains?(prompt, "3-gallon jug")
        assert String.contains?(prompt, "5-gallon jug")
        assert String.contains?(prompt, "4 gallons")
        assert String.contains?(prompt, "step by step")
        
        {:ok, %Req.Response{body: "Solution", private: %{req_llm: %{usage: %{tokens: %{}}}}}}
      end)

      result = Reasoning.verify(model, [])
      assert {:ok, _response_data} = result
    end
  end
end
