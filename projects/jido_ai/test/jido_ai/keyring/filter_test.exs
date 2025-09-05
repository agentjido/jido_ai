defmodule Jido.AI.Keyring.FilterTest do
  use ExUnit.Case, async: true
  
  # Skip this entire test module since Keyring has been extracted to Kagi project
  @moduletag :skip

  alias Jido.AI.Keyring.Filter

  describe "format/4" do
    test "formats basic log message" do
      result = Filter.format(:info, "test message", {{2023, 1, 1}, {10, 0, 0, 0}}, [])
      assert result == "[info] test message []\n"
    end

    test "formats log message with metadata" do
      metadata = [user: "john", id: 123]
      result = Filter.format(:error, "test error", {{2023, 1, 1}, {10, 0, 0, 0}}, metadata)
      assert result == "[error] test error [user: \"john\", id: 123]\n"
    end

    test "formats log message without sanitizing message text" do
      message = "Login successful"
      result = Filter.format(:info, message, {{2023, 1, 1}, {10, 0, 0, 0}}, [])
      assert result == "[info] Login successful []\n"
    end

    test "sanitizes sensitive data in metadata" do
      metadata = [api_key: "secret123", user: "john"]
      result = Filter.format(:warn, "test", {{2023, 1, 1}, {10, 0, 0, 0}}, metadata)
      assert String.contains?(result, "[REDACTED]")
      assert String.contains?(result, "john")
    end

    test "handles empty metadata" do
      result = Filter.format(:debug, "test", {{2023, 1, 1}, {10, 0, 0, 0}}, [])
      assert result == "[debug] test []\n"
    end
  end

  describe "filter_sensitive_data/1" do
    test "filters logger event tuple" do
      log_event =
        {:info, self(), {Logger, "api_key: secret123", {{2023, 1, 1}, {12, 0, 0, 0}}, [token: "abc123"]}}

      {level, gl, {Logger, filtered_msg, _ts, filtered_md}} =
        Filter.filter_sensitive_data(log_event)

      assert level == :info
      assert gl == self()
      assert filtered_msg == "api_key: secret123"
      assert filtered_md[:token] == "[REDACTED]"
    end

    test "passes through non-logger events unchanged" do
      other_event = {:some, :other, :tuple}
      result = Filter.filter_sensitive_data(other_event)
      assert result == other_event
    end
  end

  describe "sanitize_data/1" do
    test "sanitizes maps with sensitive keys" do
      data = %{
        "api_key" => "secret123",
        "username" => "john",
        "password" => "pass123"
      }

      result = Filter.sanitize_data(data)

      assert result["api_key"] == "[REDACTED]"
      assert result["username"] == "john"
      assert result["password"] == "[REDACTED]"
    end

    test "recursively sanitizes nested maps" do
      data = %{
        "user" => %{
          "name" => "john",
          "secret" => "hidden"
        },
        "config" => %{
          "api_token" => "abc123"
        }
      }

      result = Filter.sanitize_data(data)

      assert result["user"]["name"] == "john"
      assert result["user"]["secret"] == "[REDACTED]"
      assert result["config"]["api_token"] == "[REDACTED]"
    end

    test "sanitizes keyword lists" do
      data = [api_key: "secret", user: "john", token: "xyz"]

      result = Filter.sanitize_data(data)

      assert result[:api_key] == "[REDACTED]"
      assert result[:user] == "john"
      assert result[:token] == "[REDACTED]"
    end

    test "sanitizes regular lists" do
      data = ["normal", "api_key: secret123", "short"]

      result = Filter.sanitize_data(data)

      assert Enum.at(result, 0) == "normal"
      assert Enum.at(result, 1) == "api_key: secret123"
      assert Enum.at(result, 2) == "short"
    end

    test "sanitizes tuples" do
      data = {"api_key", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9", "normal_data"}

      result = Filter.sanitize_data(data)

      assert elem(result, 0) == "api_key"
      assert elem(result, 1) == "[REDACTED]"
      assert elem(result, 2) == "normal_data"
    end

    test "sanitizes strings with sensitive values" do
      # Long base64-like string
      sensitive_string = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
      result = Filter.sanitize_data(sensitive_string)
      assert result == "[REDACTED]"

      # Normal string
      normal_string = "hello world"
      result = Filter.sanitize_data(normal_string)
      assert result == "hello world"
    end

    test "passes through other data types unchanged" do
      assert Filter.sanitize_data(123) == 123
      assert Filter.sanitize_data(:atom) == :atom
      assert Filter.sanitize_data(nil) == nil
    end
  end

  describe "sensitive_key?/1" do
    test "identifies sensitive atom keys" do
      assert Filter.sensitive_key?(:api_key)
      assert Filter.sensitive_key?(:token)
      assert Filter.sensitive_key?(:password)
      assert Filter.sensitive_key?(:secret)
      assert Filter.sensitive_key?(:auth_token)
      assert Filter.sensitive_key?(:bearer_token)
      assert Filter.sensitive_key?(:private_key)
      assert Filter.sensitive_key?(:cert)
      assert Filter.sensitive_key?(:access_key)
      assert Filter.sensitive_key?(:encryption_key)
    end

    test "identifies sensitive string keys" do
      assert Filter.sensitive_key?("api_key")
      assert Filter.sensitive_key?("API_KEY")
      assert Filter.sensitive_key?("apiKey")
      assert Filter.sensitive_key?("oauth_token")
      assert Filter.sensitive_key?("user_password")
      assert Filter.sensitive_key?("client_secret")
      assert Filter.sensitive_key?("private_key")
      assert Filter.sensitive_key?("cert")
      assert Filter.sensitive_key?("session_key")
    end

    test "ignores non-sensitive keys" do
      refute Filter.sensitive_key?(:username)
      refute Filter.sensitive_key?(:email)
      refute Filter.sensitive_key?(:id)
      refute Filter.sensitive_key?("normal_field")
      refute Filter.sensitive_key?("user_name")
    end

    test "handles non-string/atom keys" do
      refute Filter.sensitive_key?(123)
      refute Filter.sensitive_key?(%{})
      refute Filter.sensitive_key?(nil)
    end
  end

  describe "looks_like_sensitive_value?/1" do
    test "identifies long base64-like strings" do
      assert Filter.looks_like_sensitive_value?("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9")

      assert Filter.looks_like_sensitive_value?("U2FsdGVkX1+vupppZksvRf5pq5g5XjFRIipRkwB0K1Y96Qsv2L")

      assert Filter.looks_like_sensitive_value?("dGVzdF9hcGlfa2V5XzEyMzQ1Njc4OTA")
    end

    test "identifies JWT tokens" do
      jwt =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

      assert Filter.looks_like_sensitive_value?(jwt)
    end

    test "identifies GitHub tokens" do
      assert Filter.looks_like_sensitive_value?("ghp_1234567890abcdef")
      assert Filter.looks_like_sensitive_value?("gho_1234567890abcdef")
      assert Filter.looks_like_sensitive_value?("ghu_1234567890abcdef")
      assert Filter.looks_like_sensitive_value?("ghs_1234567890abcdef")
      assert Filter.looks_like_sensitive_value?("ghr_1234567890abcdef")
      assert Filter.looks_like_sensitive_value?("glpat-1234567890abcdef")
    end

    test "identifies AWS access keys" do
      assert Filter.looks_like_sensitive_value?("AKIAIOSFODNN7EXAMPLE")
    end

    test "identifies OpenAI-style API keys" do
      assert Filter.looks_like_sensitive_value?("sk-1234567890abcdef1234567890abcdef")
    end

    test "ignores normal strings" do
      refute Filter.looks_like_sensitive_value?("hello world")
      refute Filter.looks_like_sensitive_value?("short")
      refute Filter.looks_like_sensitive_value?("user@example.com")
      refute Filter.looks_like_sensitive_value?("normal-text-123")
    end

    test "handles boundary cases" do
      # Exactly 20 characters (boundary)
      refute Filter.looks_like_sensitive_value?(String.duplicate("a", 20))

      # 21 characters (should be detected as sensitive)
      assert Filter.looks_like_sensitive_value?(String.duplicate("A", 21))

      # 50 characters without dots (should be detected as base64-like)
      assert Filter.looks_like_sensitive_value?(String.duplicate("a", 50))

      # 51 characters with proper JWT format (3 parts separated by dots)
      long_with_dots =
        String.duplicate("a", 17) <>
          "." <> String.duplicate("b", 17) <> "." <> String.duplicate("c", 17)

      assert Filter.looks_like_sensitive_value?(long_with_dots)
    end

    test "handles non-binary values" do
      refute Filter.looks_like_sensitive_value?(123)
      refute Filter.looks_like_sensitive_value?(:atom)
      refute Filter.looks_like_sensitive_value?(nil)
    end
  end

  describe "integration with logger" do
    test "can be used as logger formatter" do
      # Test that the format function returns proper IO.chardata
      result = Filter.format(:info, "test", [user: "john"], [])

      # Should be valid chardata that can be converted to string
      string_result = IO.chardata_to_string(result)
      assert is_binary(string_result)
      assert String.contains?(string_result, "[info]")
      assert String.contains?(string_result, "test")
    end

    test "handles various log levels" do
      levels = [:debug, :info, :warn, :error]

      for level <- levels do
        result = Filter.format(level, "message", {{2023, 1, 1}, {10, 0, 0, 0}}, [])
        assert String.contains?(result, "[#{level}]")
      end
    end

    test "handles various data types in logger events" do
      # Test with different message types
      result1 = Filter.format(:info, 123, {{2023, 1, 1}, {10, 0, 0, 0}}, [])
      assert String.contains?(result1, "123")

      result2 = Filter.format(:warn, :atom_message, {{2023, 1, 1}, {10, 0, 0, 0}}, [])
      assert String.contains?(result2, "atom_message")

      result3 = Filter.format(:error, "test error", {{2023, 1, 1}, {10, 0, 0, 0}}, [])
      assert String.contains?(result3, "test error")
    end
  end

  describe "comprehensive sanitization scenarios" do
    test "sanitizes complex nested structures" do
      data = %{
        "user" => %{
          "id" => 123,
          "credentials" => [
            api_key: "secret123",
            token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.signature"
          ]
        },
        "config" => {
          "normal",
          %{"password" => "hidden", "name" => "config"}
        }
      }

      result = Filter.sanitize_data(data)

      assert result["user"]["id"] == 123
      assert result["user"]["credentials"][:api_key] == "[REDACTED]"
      assert result["user"]["credentials"][:token] == "[REDACTED]"
      assert elem(result["config"], 0) == "normal"
      assert elem(result["config"], 1)["password"] == "[REDACTED]"
      assert elem(result["config"], 1)["name"] == "config"
    end

    test "handles pure keyword lists vs mixed lists" do
      # Pure keyword list gets special handling
      pure_keyword = [api_key: "secret", user: "john"]
      result1 = Filter.sanitize_data(pure_keyword)
      assert result1[:api_key] == "[REDACTED]"
      assert result1[:user] == "john"

      # Mixed list gets individual item processing
      mixed_list = [{:api_key, "secret"}, "normal string"]
      result2 = Filter.sanitize_data(mixed_list)
      # Tuples are processed element-wise, not as key-value pairs
      # :api_key is just an atom (not sensitive), "secret" is just a string (not long enough to be detected)
      assert result2 == [{:api_key, "secret"}, "normal string"]
    end

    test "handles empty structures" do
      assert Filter.sanitize_data(%{}) == %{}
      assert Filter.sanitize_data([]) == []
      assert Filter.sanitize_data({}) == {}
    end

    test "handles deeply nested structures" do
      data = %{
        "level1" => %{
          "level2" => %{
            "level3" => [
              api_token: "deep_secret",
              normal: "value"
            ]
          }
        }
      }

      result = Filter.sanitize_data(data)

      assert result["level1"]["level2"]["level3"][:api_token] == "[REDACTED]"
      assert result["level1"]["level2"]["level3"][:normal] == "value"
    end
  end

  describe "edge cases" do
    test "handles various sensitive key formats" do
      # Test different case variations that should match
      keys = [
        "API_KEY",
        "api_key",
        "apiKey",
        "TOKEN",
        "token",
        "Token",
        "PASSWORD",
        "password",
        "Password",
        "SECRET",
        "secret",
        "Secret",
        "OAUTH_TOKEN",
        "oauth_token",
        "BEARER_TOKEN",
        "bearer_token",
        "PRIVATE_KEY",
        "private_key",
        "CLIENT_SECRET",
        "client_secret"
      ]

      for key <- keys do
        assert Filter.sensitive_key?(key), "Expected #{key} to be sensitive"
      end
    end

    test "handles specific sensitive patterns" do
      # Test exact patterns from the regex
      # matches .*pass$
      assert Filter.sensitive_key?("pass")
      # matches .*pass$
      assert Filter.sensitive_key?("userpass")
      # matches .*password.*
      assert Filter.sensitive_key?("password123")
      # contains pass but not ending with pass, and not password
      refute Filter.sensitive_key?("passport")
    end
  end
end
