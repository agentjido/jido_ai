defmodule Jido.AI.Skills.BaseActionHelpersTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Skills.BaseActionHelpers

  describe "resolve_model/2" do
    test "resolves nil to default model" do
      assert {:ok, model} = BaseActionHelpers.resolve_model(nil, :fast)
      assert is_binary(model)
      assert String.contains?(model, "claude")
    end

    test "resolves atom alias to model spec" do
      assert {:ok, model} = BaseActionHelpers.resolve_model(:fast, :fast)
      assert is_binary(model)
    end

    test "passes through binary model spec" do
      assert {:ok, "openai:gpt-4"} = BaseActionHelpers.resolve_model("openai:gpt-4", :fast)
    end

    test "returns error for invalid model format" do
      assert {:error, :invalid_model_format} = BaseActionHelpers.resolve_model(123, :fast)
      assert {:error, :invalid_model_format} = BaseActionHelpers.resolve_model([:invalid], :fast)
    end
  end

  describe "build_opts/1" do
    test "builds options from params" do
      params = %{max_tokens: 1000, temperature: 0.5}
      opts = BaseActionHelpers.build_opts(params)

      assert opts[:max_tokens] == 1000
      assert opts[:temperature] == 0.5
      assert opts[:receive_timeout] == nil
    end

    test "adds receive_timeout when provided" do
      params = %{max_tokens: 1000, temperature: 0.5, timeout: 5000}
      opts = BaseActionHelpers.build_opts(params)

      assert opts[:receive_timeout] == 5000
    end

    test "handles missing optional params" do
      params = %{max_tokens: 1000}
      opts = BaseActionHelpers.build_opts(params)

      assert opts[:max_tokens] == 1000
      assert opts[:temperature] == nil
    end
  end

  describe "extract_text/1" do
    test "extracts binary content" do
      response = %{message: %{content: "Hello world"}}
      assert "Hello world" = BaseActionHelpers.extract_text(response)
    end

    test "extracts text from content list" do
      response = %{
        message: %{
          content: [
            %{type: :text, text: "Hello"},
            %{type: :text, text: "world"}
          ]
        }
      }

      # Text blocks are joined with newlines
      assert "Hello\nworld" = BaseActionHelpers.extract_text(response)
    end

    test "filters non-text blocks from content list" do
      response = %{
        message: %{
          content: [
            %{type: :text, text: "Hello"},
            %{type: :tool_use, id: "123"},
            %{type: :text, text: "world"}
          ]
        }
      }

      # Text blocks are joined with newlines, non-text blocks filtered
      assert "Hello\nworld" = BaseActionHelpers.extract_text(response)
    end

    test "returns empty string for malformed response" do
      assert "" = BaseActionHelpers.extract_text(%{})
      assert "" = BaseActionHelpers.extract_text(%{message: %{}})
      assert "" = BaseActionHelpers.extract_text(nil)
    end
  end

  describe "extract_usage/1" do
    test "extracts usage from response" do
      response = %{
        usage: %{
          input_tokens: 10,
          output_tokens: 20,
          total_tokens: 30
        }
      }

      usage = BaseActionHelpers.extract_usage(response)

      assert usage.input_tokens == 10
      assert usage.output_tokens == 20
      assert usage.total_tokens == 30
    end

    test "handles missing usage fields" do
      response = %{usage: %{input_tokens: 10}}
      usage = BaseActionHelpers.extract_usage(response)

      assert usage.input_tokens == 10
      assert usage.output_tokens == 0
      assert usage.total_tokens == 0
    end

    test "returns empty usage for malformed response" do
      usage = BaseActionHelpers.extract_usage(%{})

      assert usage.input_tokens == 0
      assert usage.output_tokens == 0
      assert usage.total_tokens == 0
    end
  end

  describe "validate_and_sanitize_input/2" do
    test "accepts valid input with prompt" do
      params = %{prompt: "Hello world"}
      assert {:ok, ^params} = BaseActionHelpers.validate_and_sanitize_input(params)
    end

    test "rejects empty prompt when required" do
      params = %{prompt: ""}
      assert {:error, :prompt_required} = BaseActionHelpers.validate_and_sanitize_input(params)
    end

    test "rejects nil prompt when required" do
      params = %{}
      assert {:error, :prompt_required} = BaseActionHelpers.validate_and_sanitize_input(params)
    end

    test "allows nil prompt when not required" do
      params = %{other: "data"}
      assert {:ok, ^params} = BaseActionHelpers.validate_and_sanitize_input(params, required_prompt: false)
    end

    test "validates system_prompt when present" do
      params = %{prompt: "Hello", system_prompt: "You are helpful"}
      assert {:ok, _} = BaseActionHelpers.validate_and_sanitize_input(params)
    end

    test "rejects dangerous characters in prompt" do
      params = %{prompt: "Hello" <> <<0>>}
      assert {:error, {:dangerous_character, _}} = BaseActionHelpers.validate_and_sanitize_input(params)
    end

    test "rejects dangerous characters in system_prompt" do
      params = %{prompt: "Hello", system_prompt: "You are" <> <<1>>}
      assert {:error, {:dangerous_character, _}} = BaseActionHelpers.validate_and_sanitize_input(params)
    end

    test "enforces max length for prompt" do
      long_prompt = String.duplicate("a", 200_000)
      params = %{prompt: long_prompt}
      assert {:error, :string_too_long} = BaseActionHelpers.validate_and_sanitize_input(params)
    end

    test "accepts valid custom max length" do
      prompt = String.duplicate("a", 100)
      params = %{prompt: prompt}
      assert {:ok, _} = BaseActionHelpers.validate_and_sanitize_input(params, max_prompt_length: 100)
    end
  end

  describe "sanitize_error/1" do
    test "returns generic message for runtime errors" do
      error = %RuntimeError{message: "Detailed internal error"}
      assert "An error occurred" = BaseActionHelpers.sanitize_error(error)
    end

    test "returns specific message for known error types" do
      assert "Request timed out" = BaseActionHelpers.sanitize_error(:timeout)
      assert "Connection failed" = BaseActionHelpers.sanitize_error(:econnrefused)
    end

    test "returns generic message for tuple errors" do
      assert "An error occurred" = BaseActionHelpers.sanitize_error({:error, :reason})
    end
  end

  describe "format_result/1" do
    test "passes through ok results" do
      result = {:ok, %{text: "Hello"}}
      assert ^result = BaseActionHelpers.format_result(result)
    end

    test "sanitizes error results" do
      result = {:error, %RuntimeError{message: "Internal error"}}
      assert {:error, "An error occurred"} = BaseActionHelpers.format_result(result)
    end

    test "sanitizes atom errors" do
      result = {:error, :timeout}
      assert {:error, "Request timed out"} = BaseActionHelpers.format_result(result)
    end
  end
end
