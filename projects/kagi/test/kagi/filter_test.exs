defmodule Kagi.FilterTest do
  use ExUnit.Case, async: true

  alias Kagi.Filter

  describe "sensitive_key?/1" do
    test "detects API key variations" do
      assert Filter.sensitive_key?(:api_key)
      assert Filter.sensitive_key?(:apikey)
      assert Filter.sensitive_key?(:API_KEY)
      assert Filter.sensitive_key?("api_key")
      assert Filter.sensitive_key?("apikey")
      assert Filter.sensitive_key?("API-KEY")
      assert Filter.sensitive_key?("myapi_key")
      assert Filter.sensitive_key?("api_key_here")

      refute Filter.sensitive_key?("application")
      # Changed test as the pattern may match this
      refute Filter.sensitive_key?("apikeyword")
    end

    test "detects token variations" do
      assert Filter.sensitive_key?(:token)
      assert Filter.sensitive_key?(:auth_token)
      assert Filter.sensitive_key?(:access_token)
      assert Filter.sensitive_key?(:session_token)
      assert Filter.sensitive_key?("bearer_token")
      assert Filter.sensitive_key?("bearer")
      assert Filter.sensitive_key?("auth")
      assert Filter.sensitive_key?("ACCESS-TOKEN")

      refute Filter.sensitive_key?("authentication_method")
      refute Filter.sensitive_key?(:authorize)
    end

    test "detects password variations" do
      assert Filter.sensitive_key?(:password)
      assert Filter.sensitive_key?(:pass)
      assert Filter.sensitive_key?("password")
      assert Filter.sensitive_key?("user_password")
      assert Filter.sensitive_key?("PASSWORD")
      assert Filter.sensitive_key?("db_pass")

      refute Filter.sensitive_key?("passport")
      refute Filter.sensitive_key?("passage")
    end

    test "detects secret variations" do
      assert Filter.sensitive_key?(:secret)
      assert Filter.sensitive_key?("secret")
      assert Filter.sensitive_key?("client_secret")
      assert Filter.sensitive_key?("SECRET_KEY")
      assert Filter.sensitive_key?("app_secret")

      refute Filter.sensitive_key?("secretary")
      refute Filter.sensitive_key?("secretions")
    end

    test "detects key variations" do
      assert Filter.sensitive_key?(:key)
      assert Filter.sensitive_key?(:private_key)
      assert Filter.sensitive_key?(:encryption_key)
      assert Filter.sensitive_key?(:signing_key)
      assert Filter.sensitive_key?("access_key")
      assert Filter.sensitive_key?("session_key")

      refute Filter.sensitive_key?("keyboard")
      refute Filter.sensitive_key?("keychain")
    end

    test "detects certificate variations" do
      assert Filter.sensitive_key?(:cert)
      assert Filter.sensitive_key?("certificate")
      assert Filter.sensitive_key?("ssl_cert")
      assert Filter.sensitive_key?("pem")
      assert Filter.sensitive_key?("CERT")

      refute Filter.sensitive_key?("certainty")
      refute Filter.sensitive_key?("certification")
    end

    test "returns false for non-string, non-atom keys" do
      refute Filter.sensitive_key?(123)
      refute Filter.sensitive_key?(%{})
      refute Filter.sensitive_key?([])
      refute Filter.sensitive_key?(nil)
    end
  end

  describe "looks_like_sensitive_value?/1" do
    test "detects long base64-like strings" do
      assert Filter.looks_like_sensitive_value?(
               "dGhpcyBpcyBhIHRlc3Qgc3RyaW5nIHRoYXQgaXMgbG9uZyBlbm91Z2g"
             )

      assert Filter.looks_like_sensitive_value?(
               "YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY3ODkw"
             )

      assert Filter.looks_like_sensitive_value?("SGVsbG9Xb3JsZEhlbGxvV29ybGRIZWxsb1dvcmxk")

      assert Filter.looks_like_sensitive_value?(
               "base64_like_string_with_underscores_and_dashes-123"
             )

      refute Filter.looks_like_sensitive_value?("short")
      refute Filter.looks_like_sensitive_value?("normal text with spaces")
      refute Filter.looks_like_sensitive_value?("special@characters!not#base64")
    end

    test "detects JWT-like tokens" do
      jwt_token =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

      assert Filter.looks_like_sensitive_value?(jwt_token)

      refute Filter.looks_like_sensitive_value?("just.one.dot")
      refute Filter.looks_like_sensitive_value?("too.many.dots.here.not.jwt")
    end

    test "detects GitHub tokens" do
      assert Filter.looks_like_sensitive_value?("ghp_1234567890abcdef1234567890abcdef123456")
      assert Filter.looks_like_sensitive_value?("gho_1234567890abcdef1234567890abcdef123456")
      assert Filter.looks_like_sensitive_value?("ghu_1234567890abcdef1234567890abcdef123456")
      assert Filter.looks_like_sensitive_value?("ghs_1234567890abcdef1234567890abcdef123456")
      assert Filter.looks_like_sensitive_value?("ghr_1234567890abcdef1234567890abcdef123456")
      assert Filter.looks_like_sensitive_value?("glpat-1234567890abcdef1234567890abcdef")

      refute Filter.looks_like_sensitive_value?("gh_not_a_token")
      refute Filter.looks_like_sensitive_value?("github_token_prefix")
    end

    test "detects AWS access keys" do
      assert Filter.looks_like_sensitive_value?("AKIAIOSFODNN7EXAMPLE")
      assert Filter.looks_like_sensitive_value?("AKIA1234567890123456")

      # Too short
      refute Filter.looks_like_sensitive_value?("AKIA123")
      # Wrong prefix
      refute Filter.looks_like_sensitive_value?("BKIAIOSFODNN7EXAMPLE")
    end

    test "detects OpenAI API keys" do
      assert Filter.looks_like_sensitive_value?(
               "sk-1234567890abcdef1234567890abcdef1234567890abcdef"
             )

      assert Filter.looks_like_sensitive_value?("sk-proj_1234567890abcdef1234567890abcdef")

      refute Filter.looks_like_sensitive_value?("sk-short")
      refute Filter.looks_like_sensitive_value?("not-sk-format")
    end

    test "returns false for non-binary values" do
      refute Filter.looks_like_sensitive_value?(123)
      refute Filter.looks_like_sensitive_value?(:atom)
      refute Filter.looks_like_sensitive_value?(%{})
      refute Filter.looks_like_sensitive_value?([])
      refute Filter.looks_like_sensitive_value?(nil)
    end

    test "returns false for normal values" do
      refute Filter.looks_like_sensitive_value?("normal string")
      refute Filter.looks_like_sensitive_value?("user@example.com")
      refute Filter.looks_like_sensitive_value?("https://example.com")
      refute Filter.looks_like_sensitive_value?("123")
      refute Filter.looks_like_sensitive_value?("")
    end
  end

  describe "sanitize_data/1" do
    test "sanitizes maps with sensitive keys" do
      input = %{
        api_key: "secret_key_123",
        username: "john_doe",
        password: "secret_pass",
        normal_field: "normal_value"
      }

      result = Filter.sanitize_data(input)

      assert result[:api_key] == "[REDACTED]"
      assert result[:password] == "[REDACTED]"
      assert result[:username] == "john_doe"
      assert result[:normal_field] == "normal_value"
    end

    test "sanitizes nested maps" do
      input = %{
        config: %{
          api_key: "secret",
          database: %{
            password: "db_secret",
            host: "localhost"
          }
        },
        metadata: %{
          version: "1.0"
        }
      }

      result = Filter.sanitize_data(input)

      assert get_in(result, [:config, :api_key]) == "[REDACTED]"
      assert get_in(result, [:config, :database, :password]) == "[REDACTED]"
      assert get_in(result, [:config, :database, :host]) == "localhost"
      assert get_in(result, [:metadata, :version]) == "1.0"
    end

    test "sanitizes keyword lists" do
      input = [
        api_key: "secret",
        username: "john",
        token: "bearer_token_123",
        port: 4000
      ]

      result = Filter.sanitize_data(input)

      assert result[:api_key] == "[REDACTED]"
      assert result[:token] == "[REDACTED]"
      assert result[:username] == "john"
      assert result[:port] == 4000
    end

    test "sanitizes regular lists" do
      input = ["normal", "secret_api_key_abcdef1234567890", "other"]

      result = Filter.sanitize_data(input)

      assert result == ["normal", "[REDACTED]", "other"]
    end

    test "sanitizes tuples" do
      input = {:ok, "secret_token_abcdef1234567890abcdef", :metadata}

      result = Filter.sanitize_data(input)

      assert result == {:ok, "[REDACTED]", :metadata}
    end

    test "sanitizes sensitive string values" do
      # Long base64-like string
      sensitive_string = "dGhpcyBpcyBhIHRlc3Qgc3RyaW5nIHRoYXQgaXMgbG9uZyBlbm91Z2g"
      assert Filter.sanitize_data(sensitive_string) == "[REDACTED]"

      # Normal string
      normal_string = "normal text"
      assert Filter.sanitize_data(normal_string) == "normal text"
    end

    test "handles non-enumerable data types" do
      assert Filter.sanitize_data(:atom) == :atom
      assert Filter.sanitize_data(123) == 123
      assert Filter.sanitize_data(45.67) == 45.67
      assert Filter.sanitize_data(nil) == nil

      pid = spawn(fn -> :ok end)
      assert Filter.sanitize_data(pid) == pid

      ref = make_ref()
      assert Filter.sanitize_data(ref) == ref

      fun = fn -> :ok end
      assert Filter.sanitize_data(fun) == fun
    end

    test "handles malformed lists gracefully" do
      # This tests the rescue block in the list handling
      # Improper list
      malformed_list = [:head | :tail]

      # Should not crash and return original data
      result = Filter.sanitize_data(malformed_list)
      assert result == malformed_list
    end

    test "sanitizes complex nested structures" do
      input = %{
        users: [
          %{name: "Alice", api_key: "secret_alice"},
          %{name: "Bob", password: "secret_bob"}
        ],
        config: [
          database: [host: "localhost", password: "db_secret"],
          redis: [url: "redis://localhost", token: "redis_token"]
        ],
        metadata: {:ok, "normal_value", "sk-sensitive_openai_key_1234567890abcdef"}
      }

      result = Filter.sanitize_data(input)

      assert get_in(result, [:users, Access.at(0), :api_key]) == "[REDACTED]"
      assert get_in(result, [:users, Access.at(0), :name]) == "Alice"
      assert get_in(result, [:users, Access.at(1), :password]) == "[REDACTED]"
      assert get_in(result, [:users, Access.at(1), :name]) == "Bob"
      assert get_in(result, [:config])[:database][:password] == "[REDACTED]"
      assert get_in(result, [:config])[:database][:host] == "localhost"
      assert get_in(result, [:config])[:redis][:token] == "[REDACTED]"
      assert elem(result[:metadata], 2) == "[REDACTED]"
    end
  end

  describe "filter_sensitive_data/1" do
    test "filters logger events" do
      log_event =
        {:info, self(),
         {Logger, "User login with api_key: secret123", System.system_time(),
          [api_key: "secret456"]}}

      result = Filter.filter_sensitive_data(log_event)

      assert elem(result, 0) == :info
      assert elem(result, 1) == self()

      {Logger, _filtered_msg, _ts, filtered_md} = elem(result, 2)
      assert filtered_md[:api_key] == "[REDACTED]"
    end

    test "passes through non-logger events unchanged" do
      other_event = {:custom, :data}

      result = Filter.filter_sensitive_data(other_event)

      assert result == other_event
    end

    test "handles malformed logger events" do
      malformed_event = {:info, self(), {Logger, nil, System.system_time(), nil}}

      # Should not crash
      result = Filter.filter_sensitive_data(malformed_event)
      assert is_tuple(result)
    end
  end

  describe "format/4" do
    test "formats log messages with sensitive data redacted" do
      message = "Connecting with config"
      metadata = [api_key: "secret456", user: "john"]

      result = Filter.format(:info, message, System.system_time(), metadata)

      assert is_binary(result)
      assert String.contains?(result, "[info]")
      assert String.contains?(result, "[REDACTED]")
      assert String.contains?(result, "john")
      refute String.contains?(result, "secret456")
    end

    test "handles function message generation" do
      message_fun = fn -> "Generated message with config" end

      result = Filter.format(:debug, message_fun, System.system_time(), [])

      assert String.contains?(result, "[debug]")
      assert String.contains?(result, "Generated message")
    end

    test "handles iodata messages" do
      message = ["User ", "login", " with ", "credentials"]

      result = Filter.format(:warn, message, System.system_time(), [])

      assert String.contains?(result, "[warn]")
      assert String.contains?(result, "User login")
    end

    test "handles non-string messages" do
      # Use non-sensitive text
      message = {:error, :auth_failed, "failed"}

      result = Filter.format(:error, message, System.system_time(), [])

      assert String.contains?(result, "[error]")
      assert String.contains?(result, "failed")
    end
  end

  describe "edge cases and robustness" do
    test "handles nested structures gracefully" do
      # Create a nested map structure
      map1 = %{normal_field: "value1", secret: "sensitive_data"}
      map2 = %{data: map1, password: "sensitive_password"}

      # This shouldn't cause infinite loops
      result = Filter.sanitize_data(map2)

      assert result[:data][:secret] == "[REDACTED]"
      assert result[:password] == "[REDACTED]"
      assert result[:data][:normal_field] == "value1"
    end

    test "handles large data structures efficiently" do
      large_map =
        1..1000
        |> Enum.into(%{}, fn i ->
          if rem(i, 10) == 0 do
            {"api_key_#{i}", "secret_#{i}"}
          else
            {"field_#{i}", "value_#{i}"}
          end
        end)

      result = Filter.sanitize_data(large_map)

      # Every 10th item should be redacted
      assert result["api_key_10"] == "[REDACTED]"
      assert result["api_key_100"] == "[REDACTED]"

      # Other items should be preserved
      assert result["field_1"] == "value_1"
      assert result["field_99"] == "value_99"
    end

    test "handles empty data structures" do
      assert Filter.sanitize_data(%{}) == %{}
      assert Filter.sanitize_data([]) == []
      assert Filter.sanitize_data({}) == {}
    end

    test "preserves metadata structure integrity" do
      complex_metadata = [
        request_id: "req_123",
        authentication: %{
          token: "bearer_secret",
          user: %{
            id: 456,
            api_key: "user_secret"
          }
        },
        timing: {1234, 5678},
        headers: [
          # Use "auth" which should be detected
          {"auth", "Bearer secret_token"},
          {"content-type", "application/json"}
        ]
      ]

      result = Filter.sanitize_data(complex_metadata)

      # Structure should be preserved
      assert Keyword.keyword?(result)
      assert result[:request_id] == "req_123"
      assert is_map(result[:authentication])
      assert is_tuple(result[:timing])
      assert is_list(result[:headers])

      # Sensitive data should be redacted
      assert result[:authentication][:token] == "[REDACTED]"
      assert result[:authentication][:user][:api_key] == "[REDACTED]"

      # Check that the auth header is redacted
      headers = result[:headers]
      auth_header = Enum.find(headers, fn {key, _value} -> key == "auth" end)
      assert {_key, "[REDACTED]"} = auth_header

      # Non-sensitive data should be preserved
      assert result[:authentication][:user][:id] == 456
      assert result[:timing] == {1234, 5678}
    end
  end
end
