defmodule JidoTest.AI.Actions.Langchain.ChatCompletionTest do
  use ExUnit.Case
  use Mimic
  require Logger
  alias Jido.AI.Actions.Langchain.ChatCompletion
  alias Jido.AI.Model
  alias Jido.AI.Prompt
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message
  alias LangChain.Chains.LLMChain
  alias Jido.Actions.Arithmetic.Add

  @moduletag :capture_log

  describe "run/2" do
    setup do
      # Copy LangChain modules for Mimic
      Mimic.copy(LangChain.ChatModels.ChatOpenAI)
      Mimic.copy(LangChain.ChatModels.ChatAnthropic)
      Mimic.copy(LangChain.Chains.LLMChain)

      # Create a mock model
      model = %Model{
        provider: :openai,
        model_id: "gpt-4",
        api_key: "test-api-key",
        temperature: 0.7,
        max_tokens: 1024,
        name: "Test Model",
        id: "test-model",
        description: "Test Model",
        created: System.system_time(:second),
        architecture: %Model.Architecture{
          modality: "text",
          tokenizer: "unknown",
          instruct_type: nil
        },
        endpoints: []
      }

      # Create a prompt
      prompt = Prompt.new(:user, "Hello, how are you?")

      # Create valid params
      params = %{
        model: model,
        prompt: prompt
      }

      # Create context
      context = %{state: %{}}

      {:ok, %{model: model, prompt: prompt, params: params, context: context}}
    end

    test "successfully processes a valid request with OpenAI model", %{
      params: params,
      context: context
    } do
      # Create expected chat model
      expected_chat_model =
        ChatOpenAI.new!(%{
          api_key: "test-api-key",
          model: "gpt-4",
          temperature: 0.7,
          max_tokens: 1024
        })

      # Create expected messages
      expected_messages = [Message.new_user!("Hello, how are you?")]

      # Create expected chain
      expected_chain = %LLMChain{
        llm: expected_chat_model,
        messages: expected_messages,
        verbose: true
      }

      # Mock the chat model creation
      expect(ChatOpenAI, :new!, fn opts ->
        assert opts[:api_key] == "test-api-key"
        assert opts[:model] == "gpt-4"
        assert opts[:temperature] == 0.7
        assert opts[:max_tokens] == 1024
        expected_chat_model
      end)

      # Mock the chain creation and run
      expect(LLMChain, :new!, fn opts ->
        assert opts[:llm] == expected_chat_model
        assert opts[:verbose] == true
        expected_chain
      end)

      expect(LLMChain, :add_messages, fn chain, messages ->
        assert chain == expected_chain
        assert length(messages) == 1
        assert hd(messages).content == "Hello, how are you?"
        chain
      end)

      expect(LLMChain, :run, fn chain, opts ->
        assert chain == expected_chain
        assert opts[:mode] == :single
        {:ok, %LLMChain{last_message: %Message{content: "Test response"}}}
      end)

      assert {:ok, %{content: "Test response", tool_results: []}} =
               ChatCompletion.run(params, context)
    end

    test "successfully processes a valid request with Anthropic model", %{
      params: params,
      context: context
    } do
      # Update params to use Anthropic model
      params = %{
        params
        | model: %Model{
            provider: :anthropic,
            model_id: "claude-3-sonnet-20240229",
            api_key: "test-api-key",
            temperature: 0.7,
            max_tokens: 1024,
            name: "Test Model",
            id: "test-model",
            description: "Test Model",
            created: System.system_time(:second),
            architecture: %Model.Architecture{
              modality: "text",
              tokenizer: "unknown",
              instruct_type: nil
            },
            endpoints: []
          }
      }

      # Create expected chat model
      expected_chat_model =
        ChatAnthropic.new!(%{
          api_key: "test-api-key",
          model: "claude-3-sonnet-20240229",
          temperature: 0.7,
          max_tokens: 1024
        })

      # Create expected messages
      expected_messages = [Message.new_user!("Hello, how are you?")]

      # Create expected chain
      expected_chain = %LLMChain{
        llm: expected_chat_model,
        messages: expected_messages,
        verbose: true
      }

      # Mock the chat model creation
      expect(ChatAnthropic, :new!, fn opts ->
        assert opts[:api_key] == "test-api-key"
        assert opts[:model] == "claude-3-sonnet-20240229"
        assert opts[:temperature] == 0.7
        assert opts[:max_tokens] == 1024
        expected_chat_model
      end)

      # Mock the chain creation and run
      expect(LLMChain, :new!, fn opts ->
        assert opts[:llm] == expected_chat_model
        assert opts[:verbose] == true
        expected_chain
      end)

      expect(LLMChain, :add_messages, fn chain, messages ->
        assert chain == expected_chain
        assert length(messages) == 1
        assert hd(messages).content == "Hello, how are you?"
        chain
      end)

      expect(LLMChain, :run, fn chain, opts ->
        assert chain == expected_chain
        assert opts[:mode] == :single
        {:ok, %LLMChain{last_message: %Message{content: "Test response"}}}
      end)

      assert {:ok, %{content: "Test response", tool_results: []}} =
               ChatCompletion.run(params, context)
    end

    test "successfully processes a valid request with tools", %{
      params: params,
      context: context
    } do
      # Add tools to params
      params = Map.put(params, :tools, [Add])

      # Create expected chat model
      expected_chat_model =
        ChatOpenAI.new!(%{
          api_key: "test-api-key",
          model: "gpt-4",
          temperature: 0.7,
          max_tokens: 1024
        })

      # Create expected messages
      expected_messages = [Message.new_user!("Hello, how are you?")]

      # Create expected chain
      expected_chain = %LLMChain{
        llm: expected_chat_model,
        messages: expected_messages,
        verbose: true
      }

      # Mock the chat model creation
      expect(ChatOpenAI, :new!, fn opts ->
        assert opts[:api_key] == "test-api-key"
        assert opts[:model] == "gpt-4"
        assert opts[:temperature] == 0.7
        assert opts[:max_tokens] == 1024
        expected_chat_model
      end)

      # Mock the chain creation and run
      expect(LLMChain, :new!, fn opts ->
        assert opts[:llm] == expected_chat_model
        assert opts[:verbose] == true
        expected_chain
      end)

      expect(LLMChain, :add_messages, fn chain, messages ->
        assert chain == expected_chain
        assert length(messages) == 1
        assert hd(messages).content == "Hello, how are you?"
        chain
      end)

      expect(LLMChain, :add_tools, fn chain, tools ->
        assert chain == expected_chain
        assert length(tools) == 1
        assert hd(tools).name == "add"
        chain
      end)

      expect(LLMChain, :run, fn chain, opts ->
        assert chain == expected_chain
        assert opts[:mode] == :while_needs_response
        {:ok, %LLMChain{last_message: %Message{content: "Test response"}}}
      end)

      assert {:ok, %{content: "Test response", tool_results: []}} =
               ChatCompletion.run(params, context)
    end

    test "returns error for invalid model specification", %{params: params, context: context} do
      params = %{params | model: "invalid_model"}

      assert {:error, "Invalid model specification: \"invalid_model\""} =
               ChatCompletion.run(params, context)
    end

    test "returns error for unsupported provider", %{params: params, context: context} do
      params = %{
        params
        | model: %Model{
            provider: :invalid_provider,
            model_id: "test-model",
            api_key: "test-api-key",
            temperature: 0.7,
            max_tokens: 1024,
            name: "Test Model",
            id: "test-model",
            description: "Test Model",
            created: System.system_time(:second),
            architecture: %Model.Architecture{
              modality: "text",
              tokenizer: "unknown",
              instruct_type: nil
            },
            endpoints: []
          }
      }

      assert {:error,
              "Unsupported provider: :invalid_provider. Must be one of: [:openai, :anthropic]"} =
               ChatCompletion.run(params, context)
    end

    test "handles chain run errors gracefully", %{params: params, context: context} do
      # Create expected chat model
      expected_chat_model =
        ChatOpenAI.new!(%{
          api_key: "test-api-key",
          model: "gpt-4",
          temperature: 0.7,
          max_tokens: 1024
        })

      # Create expected messages
      expected_messages = [Message.new_user!("Hello, how are you?")]

      # Create expected chain
      expected_chain = %LLMChain{
        llm: expected_chat_model,
        messages: expected_messages,
        verbose: true
      }

      # Mock the chat model creation
      expect(ChatOpenAI, :new!, fn _opts -> expected_chat_model end)

      # Mock the chain creation and run
      expect(LLMChain, :new!, fn _opts -> expected_chain end)
      expect(LLMChain, :add_messages, fn chain, _messages -> chain end)
      expect(LLMChain, :run, fn _chain, _opts -> {:error, "Chain run failed"} end)

      assert {:error, "Chain run failed"} = ChatCompletion.run(params, context)
    end
  end
end
