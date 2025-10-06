defmodule Jido.AI.ReqLlmBridge.AuthenticationTest do
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.Keyring
  alias Jido.AI.ReqLlmBridge.Authentication
  alias Jido.AI.ReqLlmBridge.SessionAuthentication

  # Add global mock setup
  setup :set_mimic_global

  setup do
    # Copy the modules we need to mock
    Mimic.copy(ReqLlmBridge.Keys)
    Mimic.copy(System)

    # Start a unique Keyring for testing
    test_keyring_name = :"test_keyring_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Keyring.start_link(name: test_keyring_name)

    on_exit(fn ->
      try do
        GenServer.stop(test_keyring_name)
      catch
        :exit, _ -> :ok
      end
    end)

    %{keyring: test_keyring_name}
  end

  describe "authenticate_for_provider/3 - unified authentication" do
    test "returns correct headers for OpenAI", %{keyring: keyring} do
      Keyring.set_session_value(keyring, :openai_api_key, "sk-test-key")

      assert {:ok, headers, "sk-test-key"} =
               Authentication.authenticate_for_provider(:openai, %{}, self())

      assert headers["authorization"] == "Bearer sk-test-key"
    end

    test "returns correct headers for Anthropic", %{keyring: keyring} do
      Keyring.set_session_value(keyring, :anthropic_api_key, "sk-ant-test")

      assert {:ok, headers, "sk-ant-test"} =
               Authentication.authenticate_for_provider(:anthropic, %{}, self())

      assert headers["x-api-key"] == "sk-ant-test"
      assert headers["anthropic-version"] == "2023-06-01"
    end

    test "handles per-request override", %{keyring: keyring} do
      # Set session value
      Keyring.set_session_value(keyring, :openai_api_key, "session-key")

      # Per-request should override... but session has precedence in our implementation
      # So this test verifies session precedence
      assert {:ok, headers, "session-key"} =
               Authentication.authenticate_for_provider(
                 :openai,
                 %{api_key: "request-key"},
                 self()
               )

      assert headers["authorization"] == "Bearer session-key"

      # Clear session to test per-request works as fallback
      Keyring.clear_session_value(keyring, :openai_api_key)

      # Mock ReqLlmBridge.Keys to return the per-request key
      expect(ReqLlmBridge.Keys, :get, fn :openai, %{api_key: "request-key"} ->
        {:ok, "request-key", :option}
      end)

      assert {:ok, headers, "request-key"} =
               Authentication.authenticate_for_provider(
                 :openai,
                 %{api_key: "request-key"},
                 self()
               )

      assert headers["authorization"] == "Bearer request-key"
    end

    test "falls back to ReqLLM when no session value", %{keyring: keyring} do
      # Clear any session values
      Keyring.clear_session_value(keyring, :openai_api_key)

      # Mock ReqLlmBridge.Keys to return a value
      expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
        {:ok, "reqllm-key", :environment}
      end)

      assert {:ok, headers, "reqllm-key"} =
               Authentication.authenticate_for_provider(:openai, %{}, self())

      assert headers["authorization"] == "Bearer reqllm-key"
    end

    test "handles unknown provider gracefully" do
      # Mock ReqLlmBridge.Keys for unknown provider
      expect(ReqLlmBridge.Keys, :get, fn :unknown_provider, %{} ->
        {:error, "API key not found"}
      end)

      assert {:error, reason} =
               Authentication.authenticate_for_provider(:unknown_provider, %{}, self())

      assert reason =~ "API key not found"
    end

    test "maps ReqLLM errors to Jido format" do
      # Mock ReqLlmBridge.Keys to return specific error
      expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
        {:error, ":api_key option or OPENAI_API_KEY env var"}
      end)

      assert {:error, "API key not found: OPENAI_API_KEY"} =
               Authentication.authenticate_for_provider(:openai, %{}, self())
    end
  end

  describe "get_authentication_headers/2 - backward compatibility" do
    test "returns headers in existing format for keyword list", %{keyring: keyring} do
      Keyring.set_session_value(keyring, :openai_api_key, "test-key")

      headers = Authentication.get_authentication_headers(:openai, [])
      assert headers["authorization"] == "Bearer test-key"
    end

    test "returns headers in existing format for map options", %{keyring: keyring} do
      Keyring.set_session_value(keyring, :anthropic_api_key, "test-key")

      headers = Authentication.get_authentication_headers(:anthropic, %{})
      assert headers["x-api-key"] == "test-key"
      assert headers["anthropic-version"] == "2023-06-01"
    end

    test "returns base headers when no authentication available" do
      # Mock ReqLlmBridge.Keys to return error
      expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
        {:error, "No key"}
      end)

      headers = Authentication.get_authentication_headers(:openai, %{})
      assert headers == %{}
    end

    test "preserves additional headers for Anthropic" do
      # Mock ReqLlmBridge.Keys to return error
      expect(ReqLlmBridge.Keys, :get, fn :anthropic, %{} ->
        {:error, "No key"}
      end)

      headers = Authentication.get_authentication_headers(:anthropic, %{})
      assert headers["anthropic-version"] == "2023-06-01"
    end
  end

  describe "validate_authentication/2 - validation preservation" do
    test "validates valid key successfully", %{keyring: keyring} do
      Keyring.set_session_value(keyring, :openai_api_key, "sk-valid-key")

      assert :ok = Authentication.validate_authentication(:openai, [])
    end

    test "returns error for empty key", %{keyring: keyring} do
      Keyring.set_session_value(keyring, :openai_api_key, "")

      # Since empty string is stored, we need to handle this case
      # The authentication will succeed but validation should catch empty
      assert {:error, "API key is empty"} =
               Authentication.validate_authentication(:openai, [])
    end

    test "returns error when no key found" do
      # Mock ReqLlmBridge.Keys to return error
      expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
        {:error, "API key not found"}
      end)

      assert {:error, _reason} =
               Authentication.validate_authentication(:openai, [])
    end

    test "handles keyword list options" do
      # Mock ReqLlmBridge.Keys to use the api_key from options
      expect(ReqLlmBridge.Keys, :get, fn :openai, %{api_key: "from-opts"} ->
        {:ok, "from-opts", :option}
      end)

      assert :ok = Authentication.validate_authentication(:openai, api_key: "from-opts")
    end
  end

  describe "resolve_provider_authentication/3 - resolution chain" do
    test "session value has highest precedence", %{keyring: keyring} do
      Keyring.set_session_value(keyring, :openai_api_key, "session-key")

      # Even if ReqLLM has a different value, session wins
      expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
        {:ok, "reqllm-key", :environment}
      end)

      assert {:ok, "session-key", :session} =
               Authentication.resolve_provider_authentication(:openai, %{}, self())
    end

    test "falls back to ReqLLM when no session", %{keyring: keyring} do
      Keyring.clear_session_value(keyring, :openai_api_key)

      expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
        {:ok, "reqllm-key", :application}
      end)

      assert {:ok, "reqllm-key", :application} =
               Authentication.resolve_provider_authentication(:openai, %{}, self())
    end

    test "falls back to Keyring when ReqLLM fails", %{keyring: keyring} do
      Keyring.clear_session_value(keyring, :openai_api_key)

      # Set environment value in Keyring
      stub(System, :get_env, fn "OPENAI_API_KEY" -> "env-key" end)

      # Mock ReqLlmBridge.Keys to fail
      expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
        {:error, "Not found"}
      end)

      assert {:ok, "env-key", :keyring} =
               Authentication.resolve_provider_authentication(:openai, %{}, self())
    end

    test "returns error when all sources fail" do
      # Mock all sources to fail
      expect(ReqLlmBridge.Keys, :get, fn :unknown, %{} ->
        {:error, "Not found"}
      end)

      assert {:error, _reason} =
               Authentication.resolve_provider_authentication(:unknown, %{}, self())
    end
  end

  describe "provider-specific header formatting" do
    test "OpenAI uses Bearer token format", %{keyring: keyring} do
      Keyring.set_session_value(keyring, :openai_api_key, "sk-123")

      {:ok, headers, _} = Authentication.authenticate_for_provider(:openai, %{}, self())
      assert headers["authorization"] == "Bearer sk-123"
    end

    test "Anthropic uses x-api-key format", %{keyring: keyring} do
      Keyring.set_session_value(keyring, :anthropic_api_key, "sk-ant-123")

      {:ok, headers, _} = Authentication.authenticate_for_provider(:anthropic, %{}, self())
      assert headers["x-api-key"] == "sk-ant-123"
      assert headers["anthropic-version"] == "2023-06-01"
    end

    test "Google uses x-goog-api-key format", %{keyring: keyring} do
      Keyring.set_session_value(keyring, :google_api_key, "google-123")

      {:ok, headers, _} = Authentication.authenticate_for_provider(:google, %{}, self())
      assert headers["x-goog-api-key"] == "google-123"
    end

    test "Cloudflare uses x-auth-key format", %{keyring: keyring} do
      Keyring.set_session_value(keyring, :cloudflare_api_key, "cf-123")

      {:ok, headers, _} = Authentication.authenticate_for_provider(:cloudflare, %{}, self())
      assert headers["x-auth-key"] == "cf-123"
    end

    test "OpenRouter uses Bearer token format", %{keyring: keyring} do
      Keyring.set_session_value(keyring, :openrouter_api_key, "sk-or-123")

      {:ok, headers, _} = Authentication.authenticate_for_provider(:openrouter, %{}, self())
      assert headers["authorization"] == "Bearer sk-or-123"
    end
  end

  describe "error message mapping" do
    test "maps 'empty' error correctly" do
      expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
        {:error, "OPENAI_API_KEY was found but is empty"}
      end)

      {:error, reason} = Authentication.authenticate_for_provider(:openai, %{}, self())
      assert reason == "API key is empty: OPENAI_API_KEY"
    end

    test "maps 'not found' error correctly" do
      expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
        {:error, ":api_key option or OPENAI_API_KEY env var"}
      end)

      {:error, reason} = Authentication.authenticate_for_provider(:openai, %{}, self())
      assert reason == "API key not found: OPENAI_API_KEY"
    end

    test "preserves other error messages" do
      expect(ReqLlmBridge.Keys, :get, fn :openai, %{} ->
        {:error, "Custom error message"}
      end)

      {:error, reason} = Authentication.authenticate_for_provider(:openai, %{}, self())
      assert reason == "Authentication error: Custom error message"
    end
  end

  describe "process isolation" do
    test "session values are process-specific", %{keyring: keyring} do
      # Set value in current process
      Keyring.set_session_value(keyring, :openai_api_key, "process1-key", self())

      # Spawn another process
      task =
        Task.async(fn ->
          # Should not see the other process's session value
          case Authentication.resolve_provider_authentication(:openai, %{}, self()) do
            {:ok, _, :session} -> :has_session
            _ -> :no_session
          end
        end)

      result = Task.await(task)
      assert result == :no_session
    end

    test "different processes can have different session values", %{keyring: keyring} do
      # Set value in current process
      Keyring.set_session_value(keyring, :openai_api_key, "main-key", self())

      # Verify in another process
      task =
        Task.async(fn ->
          # Set different value in this process
          Keyring.set_session_value(keyring, :openai_api_key, "task-key", self())

          case Authentication.authenticate_for_provider(:openai, %{}, self()) do
            {:ok, _, key} -> key
            _ -> nil
          end
        end)

      task_key = Task.await(task)
      assert task_key == "task-key"

      # Main process should still have its own key
      {:ok, _, main_key} = Authentication.authenticate_for_provider(:openai, %{}, self())
      assert main_key == "main-key"
    end
  end
end
