defmodule JidoTest.AI.Actions.OpenaiEx.ChatCompletionTest do
  use ExUnit.Case
  use Mimic
  require Logger
  alias Jido.AI.Actions.OpenaiEx.ChatCompletion
  alias Jido.AI.Model
  alias Jido.AI.Prompt
  alias OpenaiEx.Chat
  alias OpenaiEx.ChatMessage
  alias Jido.Actions.Arithmetic.Add

  # Define test response model at module level
  defmodule TestResponse do
    use Ecto.Schema

    embedded_schema do
      field :message, :string
    end
  end

  @moduletag :capture_log

  # Add global mock setup
  setup :set_mimic_global

  describe "run/2" do
    setup do
      # Copy OpenaiEx module for Mimic
      Mimic.copy(OpenaiEx)
      Mimic.copy(OpenaiEx.Chat.Completions)

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

      # Create valid messages
      messages = [
        %{role: :user, content: "Hello, how are you?"},
        %{role: :assistant, content: "I'm doing well, thank you!"}
      ]

      # Create valid params
      params = %{
        model: model,
        messages: messages
      }

      # Create context
      context = %{state: %{}}

      {:ok, %{model: model, messages: messages, params: params, context: context}}
    end

    test "successfully processes a valid request with OpenAI model", %{
      params: params,
      context: context
    } do
      # Create expected chat request
      expected_messages = [
        ChatMessage.user("Hello, how are you?"),
        ChatMessage.assistant("I'm doing well, thank you!")
      ]

      expected_req =
        Chat.Completions.new(
          model: "gpt-4",
          messages: expected_messages,
          temperature: 0.7,
          max_tokens: 1024
        )

      # Mock the OpenAI client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)

      expect(OpenaiEx.Chat.Completions, :create, fn _client, ^expected_req ->
        {:ok, %{choices: [%{message: %{content: "Test response"}}]}}
      end)

      assert {:ok, %{content: "Test response", tool_results: []}} =
               ChatCompletion.run(params, context)
    end

    test "successfully processes a valid request with prompt", %{model: model, context: context} do
      # Create a prompt
      prompt = Prompt.new(:user, "Hello, how are you?")

      params = %{
        model: model,
        prompt: prompt
      }

      # Create expected chat request
      expected_messages = [ChatMessage.user("Hello, how are you?")]

      expected_req =
        Chat.Completions.new(
          model: "gpt-4",
          messages: expected_messages,
          temperature: 0.7,
          max_tokens: 1024
        )

      # Mock the OpenAI client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)

      expect(OpenaiEx.Chat.Completions, :create, fn _client, ^expected_req ->
        {:ok, %{choices: [%{message: %{content: "Test response"}}]}}
      end)

      assert {:ok, %{content: "Test response", tool_results: []}} =
               ChatCompletion.run(params, context)
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
        prompt: prompt
      }

      # Create expected chat request
      expected_messages = [ChatMessage.user("Hello Alice")]

      expected_req =
        Chat.Completions.new(
          model: "gpt-4",
          messages: expected_messages,
          temperature: 0.7,
          max_tokens: 1024
        )

      # Mock the OpenAI client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)

      expect(OpenaiEx.Chat.Completions, :create, fn _client, ^expected_req ->
        {:ok, %{choices: [%{message: %{content: "Test response"}}]}}
      end)

      assert {:ok, %{content: "Test response", tool_results: []}} =
               ChatCompletion.run(params, context)
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
          stop: ["\n", "END"]
        })

      # Create expected chat request
      expected_messages = [
        ChatMessage.user("Hello, how are you?"),
        ChatMessage.assistant("I'm doing well, thank you!")
      ]

      expected_req =
        Chat.Completions.new(
          model: "gpt-4",
          messages: expected_messages,
          temperature: 0.5,
          max_tokens: 2048,
          top_p: 0.9,
          frequency_penalty: 0.5,
          presence_penalty: 0.5,
          stop: ["\n", "END"]
        )

      # Mock the OpenAI client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)

      expect(OpenaiEx.Chat.Completions, :create, fn _client, ^expected_req ->
        {:ok, %{choices: [%{message: %{content: "Test response"}}]}}
      end)

      assert {:ok, %{content: "Test response", tool_results: []}} =
               ChatCompletion.run(params, context)
    end

    test "successfully processes a valid request with OpenRouter model", %{
      params: params,
      context: context
    } do
      # Update params to use OpenRouter model
      params = %{
        params
        | model: %Model{
            provider: :openrouter,
            model_id: "anthropic/claude-3-sonnet",
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

      # Create expected chat request
      expected_messages = [
        ChatMessage.user("Hello, how are you?"),
        ChatMessage.assistant("I'm doing well, thank you!")
      ]

      expected_req =
        Chat.Completions.new(
          model: "anthropic/claude-3-sonnet",
          messages: expected_messages,
          temperature: 0.7,
          max_tokens: 1024
        )

      # Mock the OpenRouter client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)
      expect(OpenaiEx, :with_base_url, fn client, _url -> client end)
      expect(OpenaiEx, :with_additional_headers, fn client, _headers -> client end)

      expect(OpenaiEx.Chat.Completions, :create, fn _client, ^expected_req ->
        {:ok, %{choices: [%{message: %{content: "Test response"}}]}}
      end)

      assert {:ok, %{content: "Test response", tool_results: []}} =
               ChatCompletion.run(params, context)
    end

    test "handles tool calling configuration", %{params: params, context: context} do
      # Add tool configuration to params
      params = Map.put(params, :tools, [Add])

      # Log the tool conversion result
      Logger.info("Add.to_tool(): #{inspect(Add.to_tool())}")

      # Create expected chat request with tools
      expected_messages = [
        ChatMessage.user("Hello, how are you?"),
        ChatMessage.assistant("I'm doing well, thank you!")
      ]

      expected_req =
        Chat.Completions.new(
          model: "gpt-4",
          messages: expected_messages,
          temperature: 0.7,
          max_tokens: 1024
        )
        |> Map.put(:tools, [
          %{
            type: "function",
            function: %{
              name: "add",
              description: "Adds two numbers",
              parameters: %{
                type: "object",
                required: ["value", "amount"],
                properties: %{
                  "amount" => %{type: "string", description: "The second number to add"},
                  "value" => %{type: "string", description: "The first number to add"}
                }
              }
            }
          }
        ])

      # Log the expected request
      Logger.info("Expected request: #{inspect(expected_req)}")

      # Mock the OpenAI client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)

      expect(OpenaiEx.Chat.Completions, :create, fn _client, req ->
        # Log the actual request
        Logger.info("Actual request: #{inspect(req)}")
        {:ok, %{choices: [%{message: %{content: "Test response"}}]}}
      end)

      assert {:ok, %{content: "Test response", tool_results: []}} =
               ChatCompletion.run(params, context)
    end

    test "handles tool calls in response", %{params: params, context: context} do
      # Add tool configuration to params
      params = Map.put(params, :tools, [Add])

      # Log the tool conversion result
      Logger.info("Add.to_tool(): #{inspect(Add.to_tool())}")

      # Create expected chat request with tools
      expected_messages = [
        ChatMessage.user("Hello, how are you?"),
        ChatMessage.assistant("I'm doing well, thank you!")
      ]

      expected_req =
        Chat.Completions.new(
          model: "gpt-4",
          messages: expected_messages,
          temperature: 0.7,
          max_tokens: 1024
        )
        |> Map.put(:tools, [
          %{
            type: "function",
            function: %{
              name: "add",
              description: "Adds two numbers",
              parameters: %{
                type: "object",
                required: ["value", "amount"],
                properties: %{
                  "amount" => %{type: "string", description: "The second number to add"},
                  "value" => %{type: "string", description: "The first number to add"}
                }
              }
            }
          }
        ])

      # Log the expected request
      Logger.info("Expected request: #{inspect(expected_req)}")

      # Mock the OpenAI client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)

      expect(OpenaiEx.Chat.Completions, :create, fn _client, req ->
        # Log the actual request
        Logger.info("Actual request: #{inspect(req)}")

        {:ok,
         %{
           choices: [
             %{
               message: %{
                 content: "Let me calculate that for you.",
                 tool_calls: [
                   %{
                     name: "add",
                     arguments: Jason.encode!(%{"value" => "5", "amount" => "3"})
                   }
                 ]
               }
             }
           ]
         }}
      end)

      assert {:ok,
              %{
                content: "Let me calculate that for you.",
                tool_results: [%{tool: "add", result: 8}]
              }} =
               ChatCompletion.run(params, context)
    end

    test "returns error for invalid model specification", %{params: params, context: context} do
      params = %{params | model: "invalid_model"}

      assert {:error, "Invalid model specification. Must be a map or {provider, opts} tuple."} =
               ChatCompletion.run(params, context)
    end

    test "returns error for invalid provider", %{params: params, context: context} do
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
              "Invalid provider: :invalid_provider. Must be one of: [:openai, :openrouter]"} =
               ChatCompletion.run(params, context)
    end

    test "returns error for invalid messages", %{params: params, context: context} do
      params = %{params | messages: [%{invalid: "message"}]}

      assert {:error, "Invalid message format. Each message must have :role and :content fields."} =
               ChatCompletion.run(params, context)
    end

    test "returns error for missing messages and prompt", %{params: params, context: context} do
      params = Map.delete(params, :messages)

      assert {:error, "Either messages or prompt must be provided."} =
               ChatCompletion.run(params, context)
    end

    test "returns error for invalid prompt", %{model: model, context: context} do
      params = %{
        model: model,
        prompt: 123
      }

      assert {:error, "Expected a string or a Jido.AI.Prompt struct, got: 123"} =
               ChatCompletion.run(params, context)
    end
  end
end
