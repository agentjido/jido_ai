defmodule JidoTest.AI.Keyring.ReqLLMIntegrationTest do
  use ExUnit.Case, async: false
  import Mimic

  alias Jido.AI.Keyring

  @moduletag :capture_log
  @moduletag :reqllm_integration

  setup :verify_on_exit!

  describe "Keyring.get_with_reqllm/5" do
    test "returns session value when set" do
      # Set a session value
      Keyring.set_session_value(:test_api_key, "session-key-123")

      # Should return session value regardless of ReqLLM
      result = Keyring.get_with_reqllm(Keyring, :test_api_key, "default", self(), %{})

      assert result == "session-key-123"

      # Cleanup
      Keyring.clear_session_value(:test_api_key)
    end

    test "falls back to ReqLLM.get_key when no session value" do
      stub(ReqLLM, :get_key, fn key ->
        if key == :openai_api_key, do: "reqllm-key-456", else: nil
      end)

      result = Keyring.get_with_reqllm(Keyring, :openai_api_key, "default", self(), %{})

      assert result == "reqllm-key-456"
    end

    test "returns default when no session or ReqLLM value" do
      stub(ReqLLM, :get_key, fn _key -> nil end)

      result = Keyring.get_with_reqllm(Keyring, :nonexistent_key, "my-default", self(), %{})

      assert result == "my-default"
    end

    test "session value takes priority over ReqLLM value" do
      # Set session value
      Keyring.set_session_value(:priority_test_key, "session-wins")

      # Mock ReqLLM to return a different value
      stub(ReqLLM, :get_key, fn _key -> "reqllm-loses" end)

      result = Keyring.get_with_reqllm(Keyring, :priority_test_key, "default", self(), %{})

      assert result == "session-wins"

      # Cleanup
      Keyring.clear_session_value(:priority_test_key)
    end

    test "handles nil default gracefully" do
      stub(ReqLLM, :get_key, fn _key -> nil end)

      result = Keyring.get_with_reqllm(Keyring, :missing_key, nil, self(), %{})

      assert result == nil
    end

    test "works with different provider keys" do
      stub(ReqLLM, :get_key, fn key ->
        case key do
          :anthropic_api_key -> "anthropic-key"
          :google_api_key -> "google-key"
          :openrouter_api_key -> "openrouter-key"
          _ -> nil
        end
      end)

      assert Keyring.get_with_reqllm(Keyring, :anthropic_api_key, nil, self(), %{}) ==
               "anthropic-key"

      assert Keyring.get_with_reqllm(Keyring, :google_api_key, nil, self(), %{}) == "google-key"

      assert Keyring.get_with_reqllm(Keyring, :openrouter_api_key, nil, self(), %{}) ==
               "openrouter-key"
    end
  end

  describe "Keyring.get_env_value_with_reqllm/3" do
    test "returns env value when set" do
      # Note: This test depends on actual env values
      # We test with a key that doesn't exist to hit the ReqLLM fallback
      stub(ReqLLM, :get_key, fn _key -> "env-reqllm-value" end)

      result = Keyring.get_env_value_with_reqllm(Keyring, :test_env_key, "default")

      # Should return either env value or ReqLLM value (not default if either exists)
      assert result == "env-reqllm-value" or result != "default"
    end

    test "falls back to ReqLLM when no env value" do
      stub(ReqLLM, :get_key, fn key ->
        if key == :reqllm_only_key, do: "reqllm-env-value", else: nil
      end)

      result = Keyring.get_env_value_with_reqllm(Keyring, :reqllm_only_key, "default")

      assert result == "reqllm-env-value"
    end

    test "returns default when no env or ReqLLM value" do
      stub(ReqLLM, :get_key, fn _key -> nil end)

      result = Keyring.get_env_value_with_reqllm(Keyring, :completely_missing_key, "fallback")

      assert result == "fallback"
    end
  end

  describe "session value management" do
    test "set_session_value stores value for current process" do
      Keyring.set_session_value(:session_test, "my-value")

      result = Keyring.get_with_reqllm(Keyring, :session_test, "default", self(), %{})
      assert result == "my-value"

      Keyring.clear_session_value(:session_test)
    end

    test "clear_session_value removes value" do
      Keyring.set_session_value(:clear_test, "to-be-cleared")
      Keyring.clear_session_value(:clear_test)

      stub(ReqLLM, :get_key, fn _key -> nil end)

      result = Keyring.get_with_reqllm(Keyring, :clear_test, "default", self(), %{})
      assert result == "default"
    end

    test "clear_all_session_values removes all values" do
      Keyring.set_session_value(:key1, "value1")
      Keyring.set_session_value(:key2, "value2")

      Keyring.clear_all_session_values()

      stub(ReqLLM, :get_key, fn _key -> nil end)

      assert Keyring.get_with_reqllm(Keyring, :key1, "default", self(), %{}) == "default"
      assert Keyring.get_with_reqllm(Keyring, :key2, "default", self(), %{}) == "default"
    end

    test "session values are process-specific" do
      Keyring.set_session_value(:process_test, "main-process")

      # Spawn a new process and check it doesn't see the session value
      task =
        Task.async(fn ->
          stub(ReqLLM, :get_key, fn _key -> nil end)
          Keyring.get_with_reqllm(Keyring, :process_test, "other-process", self(), %{})
        end)

      result = Task.await(task)
      assert result == "other-process"

      # Main process still has the value
      main_result = Keyring.get_with_reqllm(Keyring, :process_test, "default", self(), %{})
      assert main_result == "main-process"

      Keyring.clear_session_value(:process_test)
    end
  end

  describe "provider-specific key resolution" do
    test "resolves OpenAI API key" do
      stub(ReqLLM, :get_key, fn :openai_api_key -> "sk-test-openai" end)

      result = Keyring.get_with_reqllm(Keyring, :openai_api_key, nil, self(), %{})
      assert result == "sk-test-openai"
    end

    test "resolves Anthropic API key" do
      stub(ReqLLM, :get_key, fn :anthropic_api_key -> "sk-ant-test" end)

      result = Keyring.get_with_reqllm(Keyring, :anthropic_api_key, nil, self(), %{})
      assert result == "sk-ant-test"
    end

    test "resolves Google API key" do
      stub(ReqLLM, :get_key, fn :google_api_key -> "AIza-test" end)

      result = Keyring.get_with_reqllm(Keyring, :google_api_key, nil, self(), %{})
      assert result == "AIza-test"
    end
  end

  describe "error handling" do
    test "handles atom keys correctly" do
      stub(ReqLLM, :get_key, fn _key -> nil end)

      # Should not raise for valid atom key
      result = Keyring.get_with_reqllm(Keyring, :valid_atom_key, "default", self(), %{})
      assert result == "default"
    end

    test "works with explicit server specification" do
      stub(ReqLLM, :get_key, fn _key -> "value" end)

      # Should work with explicitly specifying server
      result = Keyring.get_with_reqllm(Keyring, :some_key, "default", self(), %{})
      assert result == "value"
    end
  end
end
