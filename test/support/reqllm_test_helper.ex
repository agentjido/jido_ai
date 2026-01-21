defmodule JidoTest.ReqLLMTestHelper do
  @moduledoc """
  Helper functions for ReqLLM integration tests.

  Provides setup, mocking, and assertions for testing ReqLLM
  integration with mocked responses.

  ## Usage

      defmodule MyReqLLMTest do
        use ExUnit.Case
        import JidoTest.ReqLLMTestHelper

        setup :verify_on_exit!

        test "chat completion works" do
          mock_generate_text(mock_chat_response("Hello!"))

          {:ok, response} = MyModule.call_llm("Hi")
          assert response.content == "Hello!"
        end
      end
  """

  import Mimic
  import ExUnit.Assertions

  alias Jido.AI.Prompt

  @doc """
  Sets up mocked ReqLLM.generate_text responses.

  ## Parameters
  - `response` - The response to return (use `mock_chat_response/2` to create)

  ## Examples

      mock_generate_text(mock_chat_response("Hello!"))
      mock_generate_text({:error, "API error"})
  """
  def mock_generate_text(response) do
    stub(ReqLLM, :generate_text, fn _model, _messages, _opts ->
      case response do
        {:error, _} = error -> error
        response -> {:ok, response}
      end
    end)
  end

  @doc """
  Sets up mocked ReqLLM.generate_text with custom function.

  ## Parameters
  - `fun` - Function that receives (model, messages, opts) and returns response

  ## Examples

      mock_generate_text_fn(fn model, messages, _opts ->
        {:ok, %{content: "Response for \#{model}"}}
      end)
  """
  def mock_generate_text_fn(fun) when is_function(fun, 3) do
    stub(ReqLLM, :generate_text, fun)
  end

  @doc """
  Sets up mocked ReqLLM.stream_text responses.

  ## Parameters
  - `chunks` - List of chunks to stream (use `mock_stream_chunks/1` to create)

  ## Examples

      mock_stream_text(mock_stream_chunks(["Hello", " ", "world!"]))
  """
  def mock_stream_text(chunks) do
    stub(ReqLLM, :stream_text, fn _model, _messages, _opts ->
      {:ok, Stream.map(chunks, & &1)}
    end)
  end

  @doc """
  Sets up mocked ReqLLM.stream_text with error.
  """
  def mock_stream_text_error(error) do
    stub(ReqLLM, :stream_text, fn _model, _messages, _opts ->
      {:error, error}
    end)
  end

  @doc """
  Creates a test ReqLLM.Model struct for testing.

  ## Parameters
  - `provider` - Provider atom (e.g., :openai, :anthropic)
  - `opts` - Optional configuration

  ## Examples

      create_test_model(:openai)
      create_test_model(:anthropic, model: "claude-3-5-haiku", max_tokens: 2048)
  """
  def create_test_model(provider, opts \\ []) do
    model_name = Keyword.get(opts, :model, "test-model")

    %ReqLLM.Model{
      provider: provider,
      model: model_name,
      max_tokens: Keyword.get(opts, :max_tokens, 1024),
      capabilities: Keyword.get(opts, :capabilities, %{tool_call: true, reasoning: false}),
      modalities: Keyword.get(opts, :modalities, %{input: [:text], output: [:text]}),
      cost: Keyword.get(opts, :cost, %{input: 1.0, output: 2.0})
    }
  end

  @doc """
  Asserts that a value is a valid ReqLLM.Model struct.

  ## Parameters
  - `model` - The value to check

  ## Examples

      assert_reqllm_model(result)
  """
  def assert_reqllm_model(model) do
    assert is_struct(model, ReqLLM.Model), "Expected ReqLLM.Model, got: #{inspect(model)}"
    assert model.provider != nil, "Model provider is nil"
    assert model.model != nil, "Model name is nil"
    model
  end

  @doc """
  Asserts that a value is a valid Jido.AI.Model struct.

  ## Parameters
  - `model` - The value to check
  """
  def assert_jido_model(model) do
    assert is_struct(model, Jido.AI.Model), "Expected Jido.AI.Model, got: #{inspect(model)}"
    assert model.provider != nil, "Model provider is nil"
    model
  end

  @doc """
  Creates a mock chat response as a ReqLLM.Response struct.

  ## Parameters
  - `content` - The response content
  - `opts` - Optional configuration

  ## Options
  - `:finish_reason` - Finish reason (default: :stop)
  - `:input_tokens` - Input token count (default: 10)
  - `:output_tokens` - Output token count (default: 20)
  - `:total_tokens` - Total token count (default: 30)
  - `:reasoning_tokens` - Reasoning token count (default: 0)
  - `:cached_tokens` - Cached token count (default: 0)
  - `:cache_creation_tokens` - Cache creation token count (default: 0)
  - `:input_cost` - Input cost in USD (default: nil)
  - `:output_cost` - Output cost in USD (default: nil)
  - `:total_cost` - Total cost in USD (default: nil)
  - `:tool_calls` - List of tool calls (default: [])

  ## Examples

      mock_chat_response("Hello!")
      mock_chat_response("Result", tool_calls: [%{name: "search", arguments: %{}}])
      mock_chat_response("Result", input_tokens: 100, output_tokens: 50)
  """
  def mock_chat_response(content, opts \\ []) do
    tool_calls = Keyword.get(opts, :tool_calls, [])

    usage =
      %{
        input_tokens: Keyword.get(opts, :input_tokens, 10),
        output_tokens: Keyword.get(opts, :output_tokens, 20),
        total_tokens: Keyword.get(opts, :total_tokens, 30),
        reasoning_tokens: Keyword.get(opts, :reasoning_tokens, 0),
        cached_tokens: Keyword.get(opts, :cached_tokens, 0),
        cache_creation_tokens: Keyword.get(opts, :cache_creation_tokens, 0)
      }
      |> maybe_add_cost(:input_cost, Keyword.get(opts, :input_cost))
      |> maybe_add_cost(:output_cost, Keyword.get(opts, :output_cost))
      |> maybe_add_cost(:total_cost, Keyword.get(opts, :total_cost))

    message = %ReqLLM.Message{
      role: :assistant,
      content: [ReqLLM.Message.ContentPart.text(content)],
      tool_calls: if(tool_calls == [], do: nil, else: tool_calls)
    }

    %ReqLLM.Response{
      id: "test-response-#{System.unique_integer([:positive])}",
      model: "test-model",
      context: ReqLLM.Context.new([message]),
      message: message,
      usage: usage,
      finish_reason: Keyword.get(opts, :finish_reason, :stop)
    }
  end

  defp maybe_add_cost(usage, _key, nil), do: usage
  defp maybe_add_cost(usage, key, cost), do: Map.put(usage, key, cost)

  @doc """
  Creates a mock chat response with tool calls.

  ## Parameters
  - `content` - The response content
  - `tool_calls` - List of tool call maps

  ## Examples

      mock_tool_response("I'll search for that", [
        %{name: "search", arguments: %{"query" => "weather"}}
      ])
  """
  def mock_tool_response(content, tool_calls) do
    mock_chat_response(content, tool_calls: tool_calls)
  end

  @doc """
  Creates mock streaming chunks from content parts.

  ## Parameters
  - `content_parts` - List of content strings

  ## Examples

      mock_stream_chunks(["Hello", " ", "world", "!"])
  """
  def mock_stream_chunks(content_parts) do
    content_parts
    |> Enum.with_index()
    |> Enum.map(fn {content, index} ->
      %{
        content: content,
        finish_reason: if(index == length(content_parts) - 1, do: "stop", else: nil),
        index: index,
        delta: %{content: content}
      }
    end)
  end

  @doc """
  Creates mock streaming chunks with usage info on last chunk.

  ## Parameters
  - `content_parts` - List of content strings
  - `usage` - Usage map for the final chunk

  ## Examples

      mock_stream_chunks_with_usage(["Hello", "!"], %{input_tokens: 5, output_tokens: 2})
  """
  def mock_stream_chunks_with_usage(content_parts, usage) do
    chunks = mock_stream_chunks(content_parts)

    List.update_at(chunks, -1, fn chunk ->
      Map.put(chunk, :usage, usage)
    end)
  end

  @doc """
  Asserts that a chat response has expected structure.

  ## Parameters
  - `response` - The response to check
  - `expectations` - Map of expected values

  ## Examples

      assert_chat_response(response, %{content: "Hello"})
      assert_chat_response(response, %{role: :assistant})
  """
  def assert_chat_response(response, expectations \\ %{}) do
    assert is_map(response), "Response must be a map"

    if content = expectations[:content] do
      assert response.content == content,
             "Expected content #{inspect(content)}, got #{inspect(response.content)}"
    end

    if role = expectations[:role] do
      assert response.role == role,
             "Expected role #{inspect(role)}, got #{inspect(response.role)}"
    end

    if tool_calls = expectations[:tool_calls] do
      assert response.tool_calls == tool_calls,
             "Expected tool_calls #{inspect(tool_calls)}, got #{inspect(response.tool_calls)}"
    end

    response
  end

  @doc """
  Asserts that tool calls match expected structure.

  ## Parameters
  - `tool_calls` - List of tool call maps
  - `expected_names` - List of expected tool names

  ## Examples

      assert_tool_calls(response.tool_calls, ["search", "calculate"])
  """
  def assert_tool_calls(tool_calls, expected_names) do
    assert is_list(tool_calls), "Tool calls must be a list"
    actual_names = Enum.map(tool_calls, & &1[:name])

    assert actual_names == expected_names,
           "Expected tool names #{inspect(expected_names)}, got #{inspect(actual_names)}"

    tool_calls
  end

  @doc """
  Creates a test Jido.AI.Prompt for testing.

  ## Parameters
  - `content` - The prompt content
  - `opts` - Optional configuration

  ## Examples

      create_test_prompt("What is 2+2?")
      create_test_prompt("Hello", role: :system)
  """
  def create_test_prompt(content, opts \\ []) do
    role = Keyword.get(opts, :role, :user)
    Prompt.new(role, content)
  end

  @doc """
  Sets up a complete mock environment for ReqLLM testing.

  Returns a map with test fixtures.

  ## Examples

      setup do
        {:ok, setup_reqllm_test_env()}
      end
  """
  def setup_reqllm_test_env(opts \\ []) do
    provider = Keyword.get(opts, :provider, :openai)
    model_name = Keyword.get(opts, :model, "gpt-4")
    response_content = Keyword.get(opts, :response, "Test response")

    model = create_test_model(provider, model: model_name)
    response = mock_chat_response(response_content)

    mock_generate_text(response)

    %{
      model: model,
      response: response,
      provider: provider,
      model_name: model_name
    }
  end

  @doc """
  Expects ReqLLM.generate_text to be called with specific arguments.

  ## Examples

      expect_generate_text(fn model, messages, opts ->
        assert model == "openai:gpt-4"
        assert length(messages) == 1
        {:ok, mock_chat_response("Hello")}
      end)
  """
  def expect_generate_text(fun) when is_function(fun, 3) do
    expect(ReqLLM, :generate_text, fun)
  end

  @doc """
  Expects ReqLLM.generate_text to be called n times.

  ## Examples

      expect_generate_text_times(3, fn _, _, _ ->
        {:ok, mock_chat_response("Response")}
      end)
  """
  def expect_generate_text_times(n, fun) when is_integer(n) and is_function(fun, 3) do
    expect(ReqLLM, :generate_text, n, fun)
  end

  @doc """
  Creates a mock error response.

  ## Parameters
  - `type` - Error type atom
  - `message` - Error message

  ## Examples

      mock_generate_text(mock_error_response(:rate_limit, "Too many requests"))
  """
  def mock_error_response(type, message) do
    {:error, %{type: type, message: message}}
  end

  @doc """
  Asserts model conversion from various formats works correctly.

  ## Parameters
  - `input` - Input to Model.from/1
  - `expected_provider` - Expected provider atom
  - `expected_model` - Expected model name

  ## Examples

      assert_model_conversion({:openai, [model: "gpt-4"]}, :openai, "gpt-4")
  """
  def assert_model_conversion(input, expected_provider, expected_model) do
    {:ok, model} = Jido.AI.Model.from(input)

    assert_reqllm_model(model)
    assert model.provider == expected_provider
    assert model.model == expected_model

    model
  end
end
