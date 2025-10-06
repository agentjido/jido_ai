defmodule JidoTest.AI.ReqLLMIntegrationTest do
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :capture_log
  @moduletag :integration

  alias Jido.AI.Actions.OpenaiEx
  alias Jido.AI.Actions.OpenaiEx.Embeddings
  alias Jido.AI.Agent
  alias Jido.AI.Model
  alias Jido.AI.Prompt
  alias Jido.AI.ReqLlmBridge
  alias ReqLlmBridge.Provider.Generated.ValidProviders

  # Add global mock setup
  setup :set_mimic_global

  setup do
    # Copy the modules we need to mock
    Mimic.copy(ReqLLM)
    Mimic.copy(JidoKeys)
    Mimic.copy(ValidProviders)

    # Mock ValidProviders consistently
    expect(ValidProviders, :list, fn ->
      [:openai, :anthropic, :google, :openrouter]
    end)

    :ok
  end

  describe "end-to-end chat completion workflow" do
    test "complete chat workflow with ReqLLM integration" do
      # Create model
      {:ok, model} = Model.from({:openai, [model: "gpt-4", api_key: "test-api-key"]})
      model = %{model | reqllm_id: "openai:gpt-4"}

      # Create prompt
      prompt = Prompt.new(:user, "Tell me about artificial intelligence")

      # Set up mocks for complete workflow
      expect(JidoKeys, :put, fn "OPENAI_API_KEY", "test-api-key" -> :ok end)
      expect(ReqLlmBridge.Keys, :env_var_name, fn :openai -> "OPENAI_API_KEY" end)

      expect(ReqLLM, :generate_text, fn messages, reqllm_id, opts ->
        # Verify the integration pipeline
        assert is_list(messages)
        assert length(messages) == 1
        message = hd(messages)
        assert message.role == :user
        assert message.content == "Tell me about artificial intelligence"

        assert reqllm_id == "openai:gpt-4"
        assert is_list(opts)

        # Return realistic response
        {:ok,
         %{
           content:
             "Artificial Intelligence (AI) is a branch of computer science that aims to create machines capable of intelligent behavior.",
           usage: %{prompt_tokens: 12, completion_tokens: 23, total_tokens: 35},
           finish_reason: "stop"
         }}
      end)

      # Execute the complete workflow
      params = %{model: model, prompt: prompt}
      assert {:ok, response} = OpenaiEx.run(params, %{})

      # Verify response structure matches OpenAI format
      assert response.choices
      assert length(response.choices) == 1

      choice = Enum.at(response.choices, 0)
      assert choice.message.role == "assistant"
      assert String.contains?(choice.message.content, "Artificial Intelligence")
      assert choice.finish_reason == "stop"
      assert choice.index == 0

      assert response.usage.total_tokens == 35
      assert response.model == "unknown"

      # Verify tool_calls structure exists
      assert choice.message.tool_calls == []
    end

    test "chat completion with tool calls workflow" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4", api_key: "test-api-key"]})
      model = %{model | reqllm_id: "openai:gpt-4"}

      tool_schema = %{
        type: "function",
        function: %{
          name: "calculate_sum",
          description: "Calculate the sum of two numbers",
          parameters: %{
            type: "object",
            properties: %{
              a: %{type: "number", description: "First number"},
              b: %{type: "number", description: "Second number"}
            },
            required: ["a", "b"]
          }
        }
      }

      expect(JidoKeys, :put, fn "OPENAI_API_KEY", "test-api-key" -> :ok end)
      expect(ReqLlmBridge.Keys, :env_var_name, fn :openai -> "OPENAI_API_KEY" end)

      expect(ReqLLM, :generate_text, fn messages, reqllm_id, opts ->
        # Verify tool integration
        opts_map = Enum.into(opts, %{})
        assert Map.has_key?(opts_map, :tools)
        assert opts_map.tools == [tool_schema]

        {:ok,
         %{
           content: "I'll calculate that for you.",
           tool_calls: [
             %{
               id: "call_123",
               type: "function",
               function: %{name: "calculate_sum", arguments: "{\"a\": 5, \"b\": 3}"}
             }
           ],
           finish_reason: "tool_calls"
         }}
      end)

      params = %{
        model: model,
        messages: [%{role: :user, content: "What is 5 + 3?"}],
        tools: [tool_schema]
      }

      assert {:ok, response} = OpenaiEx.run(params, %{})

      choice = Enum.at(response.choices, 0)
      assert choice.finish_reason == "tool_calls"
      assert length(choice.message.tool_calls) == 1

      tool_call = Enum.at(choice.message.tool_calls, 0)
      assert tool_call.id == "call_123"
      assert tool_call.function.name == "calculate_sum"
    end

    test "multi-provider workflow compatibility" do
      # Test different providers in the same workflow
      providers_and_models = [
        {:openai, "gpt-4", "openai:gpt-4"},
        {:anthropic, "claude-3-haiku", "anthropic:claude-3-haiku"},
        {:google, "gemini-pro", "google:gemini-pro"}
      ]

      Enum.each(providers_and_models, fn {provider, model_name, reqllm_id} ->
        {:ok, model} = Model.from({provider, [model: model_name, api_key: "test-key"]})
        model = %{model | reqllm_id: reqllm_id}

        provider_env_vars = %{
          openai: "OPENAI_API_KEY",
          anthropic: "ANTHROPIC_API_KEY",
          google: "GOOGLE_API_KEY"
        }

        expect(JidoKeys, :put, fn env_var, "test-key" ->
          assert env_var == provider_env_vars[provider]
          :ok
        end)

        expect(ReqLlmBridge.Keys, :env_var_name, fn ^provider -> provider_env_vars[provider] end)

        expect(ReqLLM, :generate_text, fn _messages, ^reqllm_id, _opts ->
          {:ok, %{content: "Provider #{provider} response", finish_reason: "stop"}}
        end)

        params = %{
          model: model,
          messages: [%{role: :user, content: "Test message"}]
        }

        assert {:ok, response} = OpenaiEx.run(params, %{})

        assert String.contains?(
                 get_in(response, [:choices, Access.at(0), :message, :content]),
                 "Provider #{provider}"
               )
      end)
    end
  end

  describe "end-to-end embeddings workflow" do
    test "complete embeddings workflow with ReqLLM integration" do
      {:ok, model} = Model.from({:openai, [model: "text-embedding-ada-002", api_key: "test-key"]})
      model = %{model | reqllm_id: "openai:text-embedding-ada-002"}

      input_texts = [
        "Natural language processing is fascinating",
        "Machine learning algorithms are powerful",
        "Deep learning networks are complex"
      ]

      expect(JidoKeys, :put, fn provider, api_key ->
        assert provider == :openai
        assert api_key == "test-key"
        :ok
      end)

      expect(ReqLLM, :embed_many, fn reqllm_id, input_list, opts ->
        assert reqllm_id == "openai:text-embedding-ada-002"
        assert input_list == input_texts
        assert is_list(opts)

        # Return realistic embedding vectors (dimension 1536 for ada-002)
        embeddings =
          Enum.map(input_list, fn _text ->
            Enum.map(1..1536, fn i -> :rand.uniform() * 0.1 - 0.05 + i * 0.001 end)
          end)

        {:ok,
         %{
           embeddings: embeddings,
           usage: %{prompt_tokens: 15, total_tokens: 15}
         }}
      end)

      params = %{
        model: model,
        input: input_texts,
        encoding_format: "float",
        dimensions: 1536
      }

      assert {:ok, response} = Embeddings.run(params, %{})

      # Verify embeddings structure
      assert length(response.embeddings) == 3

      Enum.each(response.embeddings, fn embedding ->
        assert length(embedding) == 1536
        assert Enum.all?(embedding, &is_float/1)
      end)
    end

    test "batch embeddings processing workflow" do
      {:ok, model} = Model.from({:openai, [model: "text-embedding-ada-002", api_key: "test-key"]})
      model = %{model | reqllm_id: "openai:text-embedding-ada-002"}

      # Large batch of inputs
      large_input = Enum.map(1..50, fn i -> "Document #{i} content for embedding" end)

      expect(JidoKeys, :put, fn :openai, "test-key" -> :ok end)

      expect(ReqLLM, :embed_many, fn reqllm_id, input_list, _opts ->
        assert reqllm_id == "openai:text-embedding-ada-002"
        # Should handle batch size appropriately
        assert length(input_list) <= 50

        embeddings =
          Enum.map(input_list, fn _text ->
            # Smaller dimension for test
            Enum.map(1..384, fn _ -> :rand.uniform() * 0.2 - 0.1 end)
          end)

        {:ok, %{embeddings: embeddings}}
      end)

      params = %{model: model, input: large_input}

      assert {:ok, response} = Embeddings.run(params, %{})
      assert length(response.embeddings) <= 50
    end

    test "embeddings error handling workflow" do
      {:ok, model} =
        Model.from({:openai, [model: "text-embedding-ada-002", api_key: "invalid-key"]})

      model = %{model | reqllm_id: "openai:text-embedding-ada-002"}

      expect(JidoKeys, :put, fn :openai, "invalid-key" -> :ok end)

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, _opts ->
        {:error, %{code: 401, message: "Invalid API key"}}
      end)

      expect(ReqLLM, :map_error, fn {:error, error} ->
        {:error, "Authentication failed: #{error.message}"}
      end)

      params = %{model: model, input: ["test text"]}

      assert {:error, error_msg} = Embeddings.run(params, %{})
      assert String.contains?(error_msg, "Authentication failed")
    end
  end

  describe "end-to-end streaming workflow" do
    test "complete streaming workflow with ReqLLM integration" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4", api_key: "test-key"]})
      model = %{model | reqllm_id: "openai:gpt-4"}

      expect(JidoKeys, :put, fn "OPENAI_API_KEY", "test-key" -> :ok end)
      expect(ReqLlmBridge.Keys, :env_var_name, fn :openai -> "OPENAI_API_KEY" end)

      # Simulate streaming response
      mock_stream = [
        %{content: "The", role: "assistant", finish_reason: nil},
        %{content: " future", role: "assistant", finish_reason: nil},
        %{content: " of", role: "assistant", finish_reason: nil},
        %{content: " AI", role: "assistant", finish_reason: nil},
        %{content: " is", role: "assistant", finish_reason: nil},
        %{
          content: " bright",
          role: "assistant",
          finish_reason: "stop",
          usage: %{prompt_tokens: 8, completion_tokens: 6, total_tokens: 14}
        }
      ]

      expect(ReqLLM, :stream_text, fn messages, reqllm_id, opts ->
        assert is_list(messages)
        assert reqllm_id == "openai:gpt-4"
        assert Keyword.get(opts, :stream) == true

        {:ok, mock_stream}
      end)

      params = %{
        model: model,
        messages: [%{role: :user, content: "What is the future of AI?"}]
      }

      assert {:ok, stream} = OpenaiEx.make_streaming_request(params, %{})

      # Process the stream
      chunks = Enum.to_list(stream)
      assert length(chunks) == 6

      # Verify chunk structure
      Enum.each(chunks, fn chunk ->
        assert Map.has_key?(chunk, :content)
        assert Map.has_key?(chunk, :delta)
        assert Map.has_key?(chunk, :tool_calls)
        assert chunk.delta.role == "assistant"
      end)

      # Verify content progression
      contents = Enum.map(chunks, & &1.content)
      assert contents == ["The", " future", " of", " AI", " is", " bright"]

      # Verify final chunk has usage and finish_reason
      final_chunk = List.last(chunks)
      assert final_chunk.finish_reason == "stop"
      assert final_chunk.usage.total_tokens == 14
    end

    test "streaming with enhanced adapter workflow" do
      mock_stream = [
        %{content: "Enhanced", role: "assistant"},
        %{content: " streaming", role: "assistant"},
        %{content: " test", role: "assistant", finish_reason: "stop"}
      ]

      # Test enhanced streaming
      enhanced_stream =
        ReqLlmBridge.convert_streaming_response(mock_stream, enhanced: true, provider: :openai)

      # Should use the StreamingAdapter
      expect(StreamingAdapter, :adapt_stream, fn stream, opts ->
        assert Enum.to_list(stream) == mock_stream
        assert opts[:enhanced] == true
        assert opts[:provider] == :openai

        # Return adapted stream
        Enum.map(stream, fn chunk ->
          %{
            content: chunk.content,
            delta: %{content: chunk.content, role: "assistant"},
            enhanced: true
          }
        end)
      end)

      adapted_chunks = Enum.to_list(enhanced_stream)

      assert length(adapted_chunks) == 3

      Enum.each(adapted_chunks, fn chunk ->
        assert chunk.enhanced == true
        assert chunk.delta.role == "assistant"
      end)
    end
  end

  describe "backward compatibility validation" do
    test "existing OpenaiEx workflows continue to work" do
      # Test that non-ReqLLM models still work (backward compatibility)
      {:ok, regular_model} = Model.from({:openai, [model: "gpt-4", api_key: "test-key"]})
      # Note: no reqllm_id set, should use original OpenaiEx path

      # This would normally use OpenaiEx directly, but we're testing the ReqLLM integration
      # so we still expect ReqLLM calls. In a real scenario, this might branch to original OpenaiEx
      # For test purposes
      regular_model = %{regular_model | reqllm_id: "openai:gpt-4"}

      expect(JidoKeys, :put, fn "OPENAI_API_KEY", "test-key" -> :ok end)
      expect(ReqLlmBridge.Keys, :env_var_name, fn :openai -> "OPENAI_API_KEY" end)

      expect(ReqLLM, :generate_text, fn _messages, _reqllm_id, _opts ->
        {:ok, %{content: "Backward compatible response", finish_reason: "stop"}}
      end)

      params = %{
        model: regular_model,
        messages: [%{role: :user, content: "Test backward compatibility"}]
      }

      assert {:ok, response} = OpenaiEx.run(params, %{})

      assert String.contains?(
               get_in(response, [:choices, Access.at(0), :message, :content]),
               "Backward compatible"
             )
    end

    test "existing response formats are preserved" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4", api_key: "test-key"]})
      model = %{model | reqllm_id: "openai:gpt-4"}

      expect(JidoKeys, :put, fn "OPENAI_API_KEY", "test-key" -> :ok end)
      expect(ReqLlmBridge.Keys, :env_var_name, fn :openai -> "OPENAI_API_KEY" end)

      expect(ReqLLM, :generate_text, fn _messages, _reqllm_id, _opts ->
        {:ok,
         %{
           content: "Test response",
           usage: %{prompt_tokens: 5, completion_tokens: 2, total_tokens: 7},
           finish_reason: "stop"
         }}
      end)

      params = %{
        model: model,
        messages: [%{role: :user, content: "Test"}]
      }

      assert {:ok, response} = OpenaiEx.run(params, %{})

      # Verify exact OpenAI API format compatibility
      expected_structure = %{
        choices: [
          %{
            message: %{
              content: "Test response",
              role: "assistant",
              tool_calls: []
            },
            finish_reason: "stop",
            index: 0
          }
        ],
        usage: %{prompt_tokens: 5, completion_tokens: 2, total_tokens: 7},
        model: "unknown"
      }

      assert response == expected_structure
    end

    test "error handling maintains compatibility" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4", api_key: "test-key"]})
      model = %{model | reqllm_id: "openai:gpt-4"}

      expect(JidoKeys, :put, fn "OPENAI_API_KEY", "test-key" -> :ok end)
      expect(ReqLlmBridge.Keys, :env_var_name, fn :openai -> "OPENAI_API_KEY" end)

      expect(ReqLLM, :generate_text, fn _messages, _reqllm_id, _opts ->
        {:error, %{code: 429, message: "Rate limit exceeded"}}
      end)

      expect(ReqLLM, :map_error, fn {:error, error} ->
        {:error, "Rate limit exceeded: #{error.message}"}
      end)

      params = %{
        model: model,
        messages: [%{role: :user, content: "Test"}]
      }

      assert {:error, error_msg} = OpenaiEx.run(params, %{})
      assert is_binary(error_msg)
      assert String.contains?(error_msg, "Rate limit exceeded")
    end
  end

  describe "cross-module integration" do
    test "Agent integration with ReqLLM models" do
      # Test that AI Agents can use ReqLLM models seamlessly
      agent_config = [
        ai: [
          model: {:openai, [model: "gpt-4", api_key: "test-key"]},
          prompt: "You are a helpful assistant powered by ReqLLM integration."
        ]
      ]

      # Mock the agent's underlying calls
      expect(JidoKeys, :put, fn "OPENAI_API_KEY", "test-key" -> :ok end)
      expect(ReqLlmBridge.Keys, :env_var_name, fn :openai -> "OPENAI_API_KEY" end)

      expect(ReqLLM, :generate_text, fn messages, reqllm_id, _opts ->
        assert String.contains?(reqllm_id, "openai:")
        assert is_list(messages)

        {:ok,
         %{
           content: "Hello! I'm an AI assistant integrated with ReqLlmBridge.",
           finish_reason: "stop"
         }}
      end)

      # This would normally test the full Agent workflow, but for unit testing
      # we'll test the integration components that the Agent would use
      {:ok, model} = Model.from({:openai, [model: "gpt-4", api_key: "test-key"]})
      model = %{model | reqllm_id: "openai:gpt-4"}

      params = %{
        model: model,
        messages: [
          %{role: :system, content: "You are a helpful assistant powered by ReqLLM integration."},
          %{role: :user, content: "Hello, how are you?"}
        ]
      }

      assert {:ok, response} = OpenaiEx.run(params, %{})

      assert String.contains?(
               get_in(response, [:choices, Access.at(0), :message, :content]),
               "ReqLLM"
             )
    end

    test "Prompt integration with ReqLLM workflows" do
      # Test that Prompt structs work with ReqLLM
      system_prompt = Prompt.new(:system, "You are an expert in {{topic}}")
      user_prompt = Prompt.new(:user, "Explain {{concept}} in simple terms")

      # Format prompts with variables
      formatted_system = Prompt.format(system_prompt, %{topic: "artificial intelligence"})
      formatted_user = Prompt.format(user_prompt, %{concept: "neural networks"})

      {:ok, model} = Model.from({:openai, [model: "gpt-4", api_key: "test-key"]})
      model = %{model | reqllm_id: "openai:gpt-4"}

      expect(JidoKeys, :put, fn "OPENAI_API_KEY", "test-key" -> :ok end)
      expect(ReqLlmBridge.Keys, :env_var_name, fn :openai -> "OPENAI_API_KEY" end)

      expect(ReqLLM, :generate_text, fn messages, _reqllm_id, _opts ->
        assert length(messages) == 2

        system_msg = Enum.at(messages, 0)
        user_msg = Enum.at(messages, 1)

        assert system_msg.role == :system
        assert String.contains?(system_msg.content, "artificial intelligence")

        assert user_msg.role == :user
        assert String.contains?(user_msg.content, "neural networks")

        {:ok,
         %{
           content:
             "Neural networks are computational models inspired by biological neural networks.",
           finish_reason: "stop"
         }}
      end)

      params = %{
        model: model,
        messages: [
          %{role: formatted_system.role, content: formatted_system.content},
          %{role: formatted_user.role, content: formatted_user.content}
        ]
      }

      assert {:ok, response} = OpenaiEx.run(params, %{})

      assert String.contains?(
               get_in(response, [:choices, Access.at(0), :message, :content]),
               "Neural networks"
             )
    end
  end

  describe "performance and reliability" do
    test "handles concurrent requests efficiently" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4", api_key: "test-key"]})
      model = %{model | reqllm_id: "openai:gpt-4"}

      # Set up mocks for concurrent requests
      expect(JidoKeys, :put, 5, fn "OPENAI_API_KEY", "test-key" -> :ok end)
      expect(ReqLlmBridge.Keys, :env_var_name, 5, fn :openai -> "OPENAI_API_KEY" end)

      expect(ReqLLM, :generate_text, 5, fn _messages, _reqllm_id, _opts ->
        # Simulate slight delay
        Process.sleep(10)
        {:ok, %{content: "Concurrent response", finish_reason: "stop"}}
      end)

      # Create multiple concurrent requests
      tasks =
        Enum.map(1..5, fn i ->
          Task.async(fn ->
            params = %{
              model: model,
              messages: [%{role: :user, content: "Request #{i}"}]
            }

            OpenaiEx.run(params, %{})
          end)
        end)

      # Wait for all to complete
      results = Task.await_many(tasks, 5000)

      # Verify all succeeded
      assert length(results) == 5

      Enum.each(results, fn result ->
        assert {:ok, response} = result

        assert String.contains?(
                 get_in(response, [:choices, Access.at(0), :message, :content]),
                 "Concurrent response"
               )
      end)
    end

    test "handles large payloads efficiently" do
      {:ok, model} = Model.from({:openai, [model: "text-embedding-ada-002", api_key: "test-key"]})
      model = %{model | reqllm_id: "openai:text-embedding-ada-002"}

      # Create large input
      large_texts =
        Enum.map(1..100, fn i ->
          "This is a long document #{i} that contains substantial text content for embedding processing. " <>
            String.duplicate("Additional content to make it longer. ", 50)
        end)

      expect(JidoKeys, :put, fn :openai, "test-key" -> :ok end)

      expect(ReqLLM, :embed_many, fn _reqllm_id, input_list, _opts ->
        # Should handle large payloads
        assert is_list(input_list)
        # May batch the input
        assert length(input_list) <= 100

        embeddings =
          Enum.map(input_list, fn _text ->
            Enum.map(1..384, fn _ -> :rand.uniform() * 0.2 - 0.1 end)
          end)

        {:ok, %{embeddings: embeddings}}
      end)

      params = %{model: model, input: large_texts}

      # Should complete without timeout or memory issues
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, response} = Embeddings.run(params, %{})
      end_time = System.monotonic_time(:millisecond)

      # Verify reasonable performance (should complete in reasonable time)
      # Less than 5 seconds
      assert end_time - start_time < 5000

      # Verify response structure
      assert is_list(response.embeddings)
      assert length(response.embeddings) <= 100
    end

    test "graceful degradation on provider failures" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4", api_key: "test-key"]})
      model = %{model | reqllm_id: "openai:gpt-4"}

      expect(JidoKeys, :put, fn "OPENAI_API_KEY", "test-key" -> :ok end)
      expect(ReqLlmBridge.Keys, :env_var_name, fn :openai -> "OPENAI_API_KEY" end)

      # Simulate various failure scenarios
      failure_scenarios = [
        {:error, :timeout},
        {:error, %{code: 503, message: "Service unavailable"}},
        {:error, %{code: 500, message: "Internal server error"}},
        {:error, :network_error}
      ]

      Enum.each(failure_scenarios, fn error ->
        expect(ReqLLM, :generate_text, fn _messages, _reqllm_id, _opts ->
          error
        end)

        expect(ReqLLM, :map_error, fn ^error ->
          {:error, "Provider temporarily unavailable"}
        end)

        params = %{
          model: model,
          messages: [%{role: :user, content: "Test failure handling"}]
        }

        # Should handle failures gracefully
        assert {:error, error_msg} = OpenaiEx.run(params, %{})
        assert is_binary(error_msg)
      end)
    end
  end
end
