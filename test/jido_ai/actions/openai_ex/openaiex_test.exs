defmodule JidoTest.AI.Actions.OpenaiExTest do
  use ExUnit.Case, async: false
  use Mimic
  require Logger
  alias Jido.Actions.Arithmetic.Add
  alias Jido.AI.Actions.OpenaiEx, as: OpenaiExAction
  alias Jido.AI.Model
  alias Jido.AI.Prompt

  @moduletag :capture_log

  # Add global mock setup
  setup :set_mimic_global

  setup do
    # Copy ReqLLM for mocking since the implementation now uses ReqLLM
    copy(ReqLLM)
    :ok
  end

  describe "run/2" do
    setup do
      # Create a mock model
      {:ok, model} =
        Model.from({:openai, [model: "gpt-4", api_key: "test-api-key"]})

      # Create valid messages
      messages = [
        %{role: :user, content: "Hello, how are you?"},
        %{role: :assistant, content: "I'm doing well, thank you!"}
      ]

      # Create valid params
      params = %{
        model: model,
        messages: messages,
        temperature: 0.7,
        max_tokens: 1024
      }

      # Create context
      context = %{state: %{}}

      {:ok, %{model: model, messages: messages, params: params, context: context}}
    end

    test "successfully processes a valid request with OpenAI model", %{
      params: params,
      context: context
    } do
      # Mock ReqLLM since the implementation now uses ReqLLM
      expect(ReqLLM, :generate_text, fn "openai:gpt-4", _messages, _opts ->
        {:ok, %{text: "Test response", usage: %{prompt_tokens: 10, completion_tokens: 5}}}
      end)

      assert {:ok, %{content: "Test response", tool_results: []}} =
               OpenaiExAction.run(params, context)
    end

    test "successfully processes a valid request with prompt", %{model: model, context: context} do
      # Create a prompt
      prompt = Prompt.new(:user, "Hello, how are you?")

      params = %{
        model: model,
        prompt: prompt,
        temperature: 0.7,
        max_tokens: 1024
      }

      # Mock ReqLLM since the implementation now uses ReqLLM
      expect(ReqLLM, :generate_text, fn "openai:gpt-4", _messages, _opts ->
        {:ok, %{text: "Test response", usage: %{prompt_tokens: 10, completion_tokens: 5}}}
      end)

      assert {:ok, %{content: "Test response", tool_results: []}} =
               OpenaiExAction.run(params, context)
    end

    test "successfully processes a valid request with prompt and template", %{
      model: model,
      context: context
    } do
      # Create a prompt with template
      prompt =
        Prompt.new(%{
          messages: [
            %{role: :user, content: "Hello <%= @name %>", engine: :eex}
          ],
          params: %{name: "Alice"}
        })

      params = %{
        model: model,
        prompt: prompt,
        temperature: 0.7,
        max_tokens: 1024
      }

      # Mock ReqLLM since the implementation now uses ReqLLM
      expect(ReqLLM, :generate_text, fn "openai:gpt-4", _messages, _opts ->
        {:ok, %{text: "Test response", usage: %{prompt_tokens: 10, completion_tokens: 5}}}
      end)

      assert {:ok, %{content: "Test response", tool_results: []}} =
               OpenaiExAction.run(params, context)
    end

    test "successfully processes a valid request with additional parameters", %{
      params: params,
      context: context
    } do
      # Add additional parameters
      params =
        Map.merge(params, %{
          temperature: 0.5,
          max_tokens: 2048,
          top_p: 0.9,
          frequency_penalty: 0.5,
          presence_penalty: 0.5,
          stop: ["\n", "END"],
          response_format: :json,
          seed: 123
        })

      # Mock ReqLLM since the implementation now uses ReqLLM
      expect(ReqLLM, :generate_text, fn "openai:gpt-4", _messages, _opts ->
        {:ok, %{text: "Test response", usage: %{prompt_tokens: 10, completion_tokens: 5}}}
      end)

      assert {:ok, %{content: "Test response", tool_results: []}} =
               OpenaiExAction.run(params, context)
    end

    test "successfully processes a streaming request", %{params: params, context: context} do
      # Add streaming parameter
      params = Map.put(params, :stream, true)

      # Mock ReqLLM.stream_text (not generate_text) for streaming
      expect(ReqLLM, :stream_text, fn "openai:gpt-4", _messages, opts ->
        # Verify streaming is enabled
        assert opts[:stream] == true

        # Return a stream that yields chunks in ReqLLM format
        # (get_chunk_content expects delta at chunk level, not under choices)
        stream =
          Stream.map(["Hello", ", ", "world", "!"], fn chunk ->
            %{delta: %{content: chunk, role: "assistant"}}
          end)

        {:ok, stream}
      end)

      {:ok, stream} = OpenaiExAction.run(params, context)

      chunks =
        stream
        |> Enum.to_list()
        |> Enum.map(fn chunk ->
          # ReqLlmBridge transforms chunks to have delta directly
          chunk.delta.content
        end)

      assert chunks == ["Hello", ", ", "world", "!"]
    end

    test "successfully processes a valid request with OpenRouter model", %{
      params: params,
      context: context
    } do
      {:ok, model} =
        Model.from({:openrouter, [model: "anthropic/claude-3-sonnet", api_key: "test-api-key"]})

      # Update params to use OpenRouter model
      params = %{
        params
        | model: model
      }

      # Mock ReqLLM for OpenRouter
      expect(ReqLLM, :generate_text, fn "openrouter:anthropic/claude-3-sonnet",
                                        _messages,
                                        _opts ->
        {:ok, %{text: "Test response", usage: %{prompt_tokens: 10, completion_tokens: 5}}}
      end)

      assert {:ok, %{content: "Test response", tool_results: []}} =
               OpenaiExAction.run(params, context)
    end

    test "handles tool calling configuration", %{params: params, context: context} do
      # Add tool configuration to params
      params = Map.put(params, :tools, [Add])

      # Mock ReqLLM with tools
      expect(ReqLLM, :generate_text, fn "openai:gpt-4", _messages, opts ->
        # Verify tools are passed
        assert is_list(opts[:tools])
        assert length(opts[:tools]) == 1

        # Verify tool is a ReqLLM.Tool struct (converted from OpenAI format)
        tool = List.first(opts[:tools])
        assert is_struct(tool, ReqLLM.Tool)

        {:ok, %{text: "Test response", usage: %{prompt_tokens: 10, completion_tokens: 5}}}
      end)

      assert {:ok, %{content: "Test response", tool_results: []}} =
               OpenaiExAction.run(params, context)
    end

    test "handles tool calls in response", %{params: params, context: context} do
      # Add tool configuration to params
      params = Map.put(params, :tools, [Add])

      # Mock ReqLLM to return a response with tool calls in OpenAI format
      expect(ReqLLM, :generate_text, fn "openai:gpt-4", _messages, opts ->
        # Verify tools are passed
        assert is_list(opts[:tools])

        # Return response with tool calls in OpenAI format (with function key)
        {:ok,
         %{
           text: "Let me calculate that for you.",
           tool_calls: [
             %{
               id: "call_abc123",
               type: "function",
               function: %{
                 name: "add",
                 arguments: "{\"value\":\"5\",\"amount\":\"3\"}"
               }
             }
           ],
           usage: %{prompt_tokens: 10, completion_tokens: 5}
         }}
      end)

      assert {:ok,
              %{
                content: "Let me calculate that for you.",
                tool_results: [%{tool: "add", result: 8}]
              }} =
               OpenaiExAction.run(params, context)
    end

    test "returns error for invalid model specification", %{params: params, context: context} do
      params = %{params | model: "invalid_model"}

      assert {:error,
              %{
                reason: "Invalid model specification",
                details: "Must be a map or {provider, opts} tuple"
              }} =
               OpenaiExAction.run(params, context)
    end

    test "run/2 returns error for invalid provider" do
      params = %{
        model: %Model{
          id: "test-model",
          name: "Test Model",
          description: "Test Model",
          created: 1_743_009_480,
          provider: :invalid_provider,
          architecture: %Model.Architecture{
            tokenizer: "unknown",
            modality: "text",
            instruct_type: nil
          },
          model: "test-model",
          api_key: "test-api-key",
          base_url: nil,
          endpoints: nil,
          max_retries: 0,
          max_tokens: 1024,
          temperature: 0.7
        },
        messages: [
          %{role: :user, content: "Hello, how are you?"},
          %{role: :assistant, content: "I'm doing well, thank you!"}
        ],
        temperature: 0.7,
        max_tokens: 1024
      }

      context = %{state: %{}}

      assert {:error,
              %{
                reason: "Invalid provider",
                details: "Got :invalid_provider, expected one of [:openai, :openrouter, :google]"
              }} =
               OpenaiExAction.run(params, context)
    end

    test "returns error for invalid messages", %{params: params, context: context} do
      params = %{params | messages: [%{invalid: "message"}]}

      assert {:error,
              %{
                reason: "Invalid message format",
                details: "Messages must have :role and :content, got [%{invalid: \"message\"}]"
              }} =
               OpenaiExAction.run(params, context)
    end

    test "returns error for missing messages and prompt", %{params: params, context: context} do
      params = Map.delete(params, :messages)

      assert {:error,
              %{
                reason: "Missing input",
                details: "Either messages or prompt must be provided"
              }} =
               OpenaiExAction.run(params, context)
    end

    test "returns error for invalid prompt", %{model: model, context: context} do
      params = %{
        model: model,
        prompt: 123
      }

      assert {:error,
              %{
                reason: "Invalid prompt",
                details: "Expected a string or a Jido.AI.Prompt struct, got: 123"
              }} =
               OpenaiExAction.run(params, context)
    end
  end
end
