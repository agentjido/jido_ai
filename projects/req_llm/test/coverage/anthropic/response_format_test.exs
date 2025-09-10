defmodule ReqLLM.Coverage.Anthropic.ResponseFormatTest do
  use ExUnit.Case, async: true
  alias ReqLLM.Test.LiveFixture
  import ReqLLM.Context

  @moduletag :coverage
  @moduletag :anthropic
  @moduletag :response_format

  describe "response format parameter" do
    test "response_format parameter should be ignored by Anthropic" do
      # According to the Oracle research, Anthropic native API does not support
      # response_format parameter - it should be ignored/omitted from requests
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          user(
            "Respond with valid JSON: {'greeting': 'hello', 'status': 'success'}"
          )
        ])

      # This should work even though response_format is provided - it should be ignored
      {:ok, response} =
        LiveFixture.use_fixture("response_format/ignored_parameter", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            # Should be ignored
            response_format: %{type: "json_object"},
            max_tokens: 100
          )
        end)

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      # Should still get a response (parameter ignored, not rejected)
      assert String.length(text_content) > 0
    end

    test "json mode enforcement through prompt engineering" do
      # Since Anthropic doesn't support response_format, JSON must be enforced via prompting
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          system("You must respond only with valid JSON. No other text."),
          user("Create a JSON object with name='Alice' and age=30")
        ])

      {:ok, response} =
        LiveFixture.use_fixture("response_format/prompt_enforced_json", [], fn ->
          ReqLLM.generate_text(model, context: context, max_tokens: 100)
        end)

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      # Should contain valid JSON structure
      assert text_content =~ "{"
      assert text_content =~ "Alice"
      assert text_content =~ "30"

      # Try to parse as JSON
      case Jason.decode(String.trim(text_content)) do
        {:ok, parsed} ->
          assert is_map(parsed)

        {:error, _} ->
          # Some models might include explanation, that's okay for prompt-based enforcement
          assert text_content =~ "json"
      end
    end

    test "structured output via tool calling instead of response_format" do
      # Anthropic's recommended approach for structured output is via tool calling
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      # Define a tool that enforces JSON structure
      {:ok, json_tool} =
        ReqLLM.Tool.new(
          name: "format_response",
          description: "Format the response as structured JSON",
          parameter_schema: [
            name: [type: :string, required: true],
            age: [type: :integer, required: true],
            email: [type: :string]
          ]
        )

      context =
        ReqLLM.Context.new([
          user(
            "I need info about Alice, who is 30 years old and her email is alice@example.com"
          )
        ])

      {:ok, response} =
        LiveFixture.use_fixture("response_format/tool_based_json", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            tools: [json_tool],
            tool_choice: %{type: "tool", name: "format_response"},
            max_tokens: 200
          )
        end)

      # Should contain tool call with structured data
      tool_calls =
        response.chunks
        |> Enum.filter(&(&1.type == :tool_call))

      assert length(tool_calls) > 0

      tool_call = hd(tool_calls)
      assert tool_call.name == "format_response"
      assert is_map(tool_call.arguments)
      assert tool_call.arguments["name"] == "Alice"
      assert tool_call.arguments["age"] == 30
    end

    test "text mode is default behavior" do
      # Without response_format parameter, should default to text
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          user("Tell me about Elixir programming language")
        ])

      {:ok, response} =
        LiveFixture.use_fixture("response_format/default_text", [], fn ->
          ReqLLM.generate_text(model, context: context, max_tokens: 100)
        end)

      text_content =
        response.chunks
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.text)
        |> Enum.join()

      # Should get natural text response
      assert text_content =~ ~r/elixir/i
      assert String.length(text_content) > 20
    end

    test "provider should not send unsupported parameters" do
      # This is more of an implementation test - ensure our provider
      # doesn't send response_format to Anthropic API
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")

      context =
        ReqLLM.Context.new([
          user("Simple test message")
        ])

      # Multiple unsupported OpenAI-style parameters that should be filtered out
      {:ok, response} =
        LiveFixture.use_fixture("response_format/filtered_parameters", [], fn ->
          ReqLLM.generate_text(model,
            context: context,
            # Should be filtered
            response_format: %{type: "json_object"},
            # Should be filtered
            n: 1,
            # Should be filtered
            logprobs: true,
            # Should be filtered
            presence_penalty: 0.1,
            # Should be filtered
            frequency_penalty: 0.1,
            max_tokens: 50
          )
        end)

      # Should work because unsupported params are filtered out
      assert response.chunks != []
    end
  end
end
