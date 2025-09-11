defmodule JidoKeys.KeyFormatTest do
  use ExUnit.Case, async: false

  import JidoKeys.TestHelpers

  setup do
    stop_jido_keys_server()
    :ok
  end

  describe "uppercase string keys (standard environment variables)" do
    test "supports standard environment variable format" do
      with_env_vars(
        %{
          "OPENAI_API_KEY" => "sk-1234567890",
          "ANTHROPIC_API_KEY" => "sk-ant-1234567890",
          "DATABASE_URL" => "postgres://localhost:5432/mydb",
          "SECRET_KEY_BASE" => "secret123456789",
          "MY_CUSTOM_KEY" => "custom_value"
        },
        fn ->
          start_jido_keys_server()

          # Test uppercase string keys
          assert JidoKeys.get("OPENAI_API_KEY") == "sk-1234567890"
          assert JidoKeys.get("ANTHROPIC_API_KEY") == "sk-ant-1234567890"
          assert JidoKeys.get("DATABASE_URL") == "postgres://localhost:5432/mydb"
          assert JidoKeys.get("SECRET_KEY_BASE") == "secret123456789"
          assert JidoKeys.get("MY_CUSTOM_KEY") == "custom_value"
        end
      )
    end

    test "handles mixed case and special characters in environment keys" do
      with_env_vars(
        %{
          "OpenAI-API-Key" => "sk-1234567890",
          "anthropic_api_key" => "sk-ant-1234567890",
          "DATABASE.URL" => "postgres://localhost:5432/mydb",
          "secret-key-base" => "secret123456789",
          "MY_CUSTOM_KEY_123" => "custom_value"
        },
        fn ->
          start_jido_keys_server()

          # All should normalize to the same keys
          assert JidoKeys.get("OpenAI-API-Key") == "sk-1234567890"
          assert JidoKeys.get("anthropic_api_key") == "sk-ant-1234567890"
          assert JidoKeys.get("DATABASE.URL") == "postgres://localhost:5432/mydb"
          assert JidoKeys.get("secret-key-base") == "secret123456789"
          assert JidoKeys.get("MY_CUSTOM_KEY_123") == "custom_value"
        end
      )
    end

    test "supports any string key without constraints" do
      with_env_vars(
        %{
          "VERY_LONG_KEY_NAME_WITH_UNDERSCORES" => "value1",
          "key-with-dashes" => "value2",
          "key.with.dots" => "value3",
          "key with spaces" => "value4",
          "KEY@WITH#SPECIAL$CHARS" => "value5",
          "123_NUMERIC_START" => "value6",
          "UPPERCASE_KEY" => "value7",
          "lowercase_key" => "value8",
          "MixedCaseKey" => "value9"
        },
        fn ->
          start_jido_keys_server()

          # All keys should work regardless of format
          assert JidoKeys.get("VERY_LONG_KEY_NAME_WITH_UNDERSCORES") == "value1"
          assert JidoKeys.get("key-with-dashes") == "value2"
          assert JidoKeys.get("key.with.dots") == "value3"
          assert JidoKeys.get("key with spaces") == "value4"
          assert JidoKeys.get("KEY@WITH#SPECIAL$CHARS") == "value5"
          assert JidoKeys.get("123_NUMERIC_START") == "value6"
          assert JidoKeys.get("UPPERCASE_KEY") == "value7"
          assert JidoKeys.get("lowercase_key") == "value8"
          assert JidoKeys.get("MixedCaseKey") == "value9"
        end
      )
    end
  end

  describe "key equivalence between atoms and strings" do
    test "atom and string keys access the same values" do
      with_env_vars(
        %{
          "OPENAI_API_KEY" => "sk-1234567890",
          "DATABASE_URL" => "postgres://localhost:5432/mydb",
          "SECRET_KEY_BASE" => "secret123456789"
        },
        fn ->
          start_jido_keys_server()

          # String keys
          assert JidoKeys.get("OPENAI_API_KEY") == "sk-1234567890"
          assert JidoKeys.get("DATABASE_URL") == "postgres://localhost:5432/mydb"
          assert JidoKeys.get("SECRET_KEY_BASE") == "secret123456789"

          # Atom keys (should access same values)
          assert JidoKeys.get(:openai_api_key) == "sk-1234567890"
          assert JidoKeys.get(:database_url) == "postgres://localhost:5432/mydb"
          assert JidoKeys.get(:secret_key_base) == "secret123456789"
        end
      )
    end

    test "normalized string keys are equivalent" do
      with_env_vars(
        %{
          "OPENAI_API_KEY" => "sk-1234567890"
        },
        fn ->
          start_jido_keys_server()

          # All these should access the same value
          assert JidoKeys.get("OPENAI_API_KEY") == "sk-1234567890"
          assert JidoKeys.get("openai_api_key") == "sk-1234567890"
          assert JidoKeys.get("OpenAI-API-Key") == "sk-1234567890"
          assert JidoKeys.get("openai.api.key") == "sk-1234567890"
          assert JidoKeys.get(:openai_api_key) == "sk-1234567890"
        end
      )
    end

    test "has? and has_value? work with both formats" do
      with_env_vars(
        %{
          "EXISTING_KEY" => "some_value",
          "EMPTY_KEY" => ""
        },
        fn ->
          start_jido_keys_server()

          # String keys
          assert JidoKeys.has?("EXISTING_KEY") == true
          assert JidoKeys.has?("EMPTY_KEY") == true
          assert JidoKeys.has?("MISSING_KEY") == false

          assert JidoKeys.has_value?("EXISTING_KEY") == true
          assert JidoKeys.has_value?("EMPTY_KEY") == false
          assert JidoKeys.has_value?("MISSING_KEY") == false

          # Atom keys
          assert JidoKeys.has?(:existing_key) == true
          assert JidoKeys.has?(:empty_key) == true
          assert JidoKeys.has?(:missing_key) == false

          assert JidoKeys.has_value?(:existing_key) == true
          assert JidoKeys.has_value?(:empty_key) == false
          assert JidoKeys.has_value?(:missing_key) == false
        end
      )
    end
  end

  describe "runtime key setting with different formats" do
    test "put works with both atoms and strings" do
      start_jido_keys_server()

      # String keys
      assert JidoKeys.put("RUNTIME_STRING_KEY", "string_value") == :ok
      assert JidoKeys.get("RUNTIME_STRING_KEY") == "string_value"
      # normalized
      assert JidoKeys.get("runtime_string_key") == "string_value"
      # normalized
      assert JidoKeys.get(:runtime_string_key) == "string_value"

      # Atom keys
      assert JidoKeys.put(:runtime_atom_key, "atom_value") == :ok
      assert JidoKeys.get(:runtime_atom_key) == "atom_value"
      # normalized
      assert JidoKeys.get("runtime_atom_key") == "atom_value"
      # normalized
      assert JidoKeys.get("RUNTIME_ATOM_KEY") == "atom_value"
    end

    test "put with mixed case and special characters" do
      start_jido_keys_server()

      # Various string formats
      assert JidoKeys.put("Mixed-Case_Key.123", "value1") == :ok
      assert JidoKeys.put("UPPERCASE_KEY", "value2") == :ok
      assert JidoKeys.put("lowercase_key", "value3") == :ok

      # All should be accessible via normalized form
      assert JidoKeys.get("mixed_case_key_123") == "value1"
      assert JidoKeys.get("uppercase_key") == "value2"
      assert JidoKeys.get("lowercase_key") == "value3"

      # And via atoms
      assert JidoKeys.get(:mixed_case_key_123) == "value1"
      assert JidoKeys.get(:uppercase_key) == "value2"
      assert JidoKeys.get(:lowercase_key) == "value3"
    end
  end

  describe "list function includes all key formats" do
    test "list shows normalized keys regardless of input format" do
      with_env_vars(
        %{
          "UPPERCASE_KEY" => "value1",
          "lowercase_key" => "value2",
          "Mixed-Case.Key" => "value3"
        },
        fn ->
          start_jido_keys_server()

          # Add some runtime keys
          JidoKeys.put("RUNTIME_KEY", "value4")
          JidoKeys.put(:runtime_atom, "value5")

          keys = JidoKeys.list()

          # All should be normalized to lowercase with underscores
          assert "uppercase_key" in keys
          assert "lowercase_key" in keys
          assert "mixed_case_key" in keys
          assert "runtime_key" in keys
          assert "runtime_atom" in keys

          # Should not contain the original mixed case versions
          refute "UPPERCASE_KEY" in keys
          refute "Mixed-Case.Key" in keys
          refute "RUNTIME_KEY" in keys
        end
      )
    end
  end

  describe "error handling with different key formats" do
    test "get! raises for missing keys in both formats" do
      start_jido_keys_server()

      # String keys
      assert_raise ArgumentError, "Configuration key \"MISSING_STRING\" not found", fn ->
        JidoKeys.get!("MISSING_STRING")
      end

      # Atom keys
      assert_raise ArgumentError, "Configuration key :missing_atom not found", fn ->
        JidoKeys.get!(:missing_atom)
      end
    end
  end

  describe "integration with LLM key normalization" do
    test "LLM keys work with both atom and string formats" do
      with_env_vars(
        %{
          "OPENAI_API_KEY" => "sk-1234567890",
          "ANTHROPIC_API_KEY" => "sk-ant-1234567890"
        },
        fn ->
          start_jido_keys_server()

          # String access
          assert JidoKeys.get("OPENAI_API_KEY") == "sk-1234567890"
          assert JidoKeys.get("ANTHROPIC_API_KEY") == "sk-ant-1234567890"

          # Atom access
          assert JidoKeys.get(:openai_api_key) == "sk-1234567890"
          assert JidoKeys.get(:anthropic_api_key) == "sk-ant-1234567890"

          # LLM atom conversion
          assert JidoKeys.to_llm_atom("openai_api_key") == :openai_api_key
          assert JidoKeys.to_llm_atom("anthropic_api_key") == :anthropic_api_key

          # Non-LLM keys remain as strings
          assert JidoKeys.to_llm_atom("database_url") == "database_url"
          assert JidoKeys.to_llm_atom("custom_key") == "custom_key"
        end
      )
    end
  end
end
