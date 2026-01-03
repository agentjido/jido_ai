defmodule Jido.AI.ConfigTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Config

  describe "get_provider/1" do
    test "returns empty list for unconfigured provider" do
      assert Config.get_provider(:unconfigured_provider) == []
    end

    test "returns provider config when configured" do
      Application.put_env(:jido_ai, :providers, %{
        test_provider: [api_key: "test-key", base_url: "http://test.com"]
      })

      on_exit(fn -> Application.delete_env(:jido_ai, :providers) end)

      config = Config.get_provider(:test_provider)
      assert Keyword.get(config, :api_key) == "test-key"
      assert Keyword.get(config, :base_url) == "http://test.com"
    end

    test "resolves environment variables with {:system, var} tuple" do
      System.put_env("TEST_API_KEY", "env-secret-key")

      Application.put_env(:jido_ai, :providers, %{
        env_provider: [api_key: {:system, "TEST_API_KEY"}]
      })

      on_exit(fn ->
        Application.delete_env(:jido_ai, :providers)
        System.delete_env("TEST_API_KEY")
      end)

      config = Config.get_provider(:env_provider)
      assert Keyword.get(config, :api_key) == "env-secret-key"
    end

    test "resolves environment variables with default value" do
      Application.put_env(:jido_ai, :providers, %{
        default_provider: [api_key: {:system, "NONEXISTENT_VAR", "default-value"}]
      })

      on_exit(fn -> Application.delete_env(:jido_ai, :providers) end)

      config = Config.get_provider(:default_provider)
      assert Keyword.get(config, :api_key) == "default-value"
    end

    test "handles map-style provider config" do
      Application.put_env(:jido_ai, :providers, %{
        map_provider: %{api_key: "map-key", timeout: 5000}
      })

      on_exit(fn -> Application.delete_env(:jido_ai, :providers) end)

      config = Config.get_provider(:map_provider)
      assert Keyword.get(config, :api_key) == "map-key"
      assert Keyword.get(config, :timeout) == 5000
    end
  end

  describe "resolve_model/1" do
    test "passes through direct model spec strings" do
      assert Config.resolve_model("anthropic:claude-haiku-4-5") == "anthropic:claude-haiku-4-5"
      assert Config.resolve_model("openai:gpt-4") == "openai:gpt-4"
      assert Config.resolve_model("ollama:llama3") == "ollama:llama3"
    end

    test "resolves default :fast alias" do
      result = Config.resolve_model(:fast)
      assert is_binary(result)
      assert String.contains?(result, ":")
    end

    test "resolves default :capable alias" do
      result = Config.resolve_model(:capable)
      assert is_binary(result)
      assert String.contains?(result, ":")
    end

    test "resolves default :reasoning alias" do
      result = Config.resolve_model(:reasoning)
      assert is_binary(result)
      assert String.contains?(result, ":")
    end

    test "resolves custom configured alias" do
      Application.put_env(:jido_ai, :model_aliases, %{
        custom_model: "google:gemini-pro"
      })

      on_exit(fn -> Application.delete_env(:jido_ai, :model_aliases) end)

      assert Config.resolve_model(:custom_model) == "google:gemini-pro"
    end

    test "custom alias overrides default" do
      Application.put_env(:jido_ai, :model_aliases, %{
        fast: "openai:gpt-4o-mini"
      })

      on_exit(fn -> Application.delete_env(:jido_ai, :model_aliases) end)

      assert Config.resolve_model(:fast) == "openai:gpt-4o-mini"
    end

    test "raises ArgumentError for unknown alias" do
      assert_raise ArgumentError, ~r/Unknown model alias: :nonexistent/, fn ->
        Config.resolve_model(:nonexistent)
      end
    end

    test "error message includes available aliases" do
      assert_raise ArgumentError, ~r/Available aliases:/, fn ->
        Config.resolve_model(:nonexistent)
      end
    end
  end

  describe "get_model_aliases/0" do
    test "returns default aliases when not configured" do
      Application.delete_env(:jido_ai, :model_aliases)

      aliases = Config.get_model_aliases()
      assert Map.has_key?(aliases, :fast)
      assert Map.has_key?(aliases, :capable)
      assert Map.has_key?(aliases, :reasoning)
    end

    test "merges configured aliases with defaults" do
      Application.put_env(:jido_ai, :model_aliases, %{
        extra_alias: "provider:model"
      })

      on_exit(fn -> Application.delete_env(:jido_ai, :model_aliases) end)

      aliases = Config.get_model_aliases()
      assert Map.has_key?(aliases, :fast)
      assert Map.has_key?(aliases, :extra_alias)
      assert aliases[:extra_alias] == "provider:model"
    end
  end

  describe "defaults/0" do
    test "returns default settings when not configured" do
      Application.delete_env(:jido_ai, :defaults)

      defaults = Config.defaults()
      assert is_map(defaults)
      assert Map.has_key?(defaults, :temperature)
      assert Map.has_key?(defaults, :max_tokens)
    end

    test "returns default temperature value" do
      Application.delete_env(:jido_ai, :defaults)

      defaults = Config.defaults()
      assert defaults[:temperature] == 0.7
    end

    test "returns default max_tokens value" do
      Application.delete_env(:jido_ai, :defaults)

      defaults = Config.defaults()
      assert defaults[:max_tokens] == 1024
    end

    test "merges configured defaults with defaults" do
      Application.put_env(:jido_ai, :defaults, %{
        temperature: 0.5,
        custom_setting: "value"
      })

      on_exit(fn -> Application.delete_env(:jido_ai, :defaults) end)

      defaults = Config.defaults()
      assert defaults[:temperature] == 0.5
      assert defaults[:max_tokens] == 1024
      assert defaults[:custom_setting] == "value"
    end
  end

  describe "get_default/2" do
    test "returns specific default value" do
      Application.delete_env(:jido_ai, :defaults)

      assert Config.get_default(:temperature) == 0.7
      assert Config.get_default(:max_tokens) == 1024
    end

    test "returns fallback for unknown key" do
      assert Config.get_default(:unknown_key, :fallback) == :fallback
    end

    test "returns nil for unknown key without fallback" do
      assert Config.get_default(:unknown_key) == nil
    end
  end

  describe "validate/0" do
    test "returns :ok for valid default configuration" do
      Application.delete_env(:jido_ai, :model_aliases)
      Application.delete_env(:jido_ai, :defaults)

      assert Config.validate() == :ok
    end

    test "returns :ok for valid custom configuration" do
      Application.put_env(:jido_ai, :model_aliases, %{
        custom: "provider:model-name"
      })

      Application.put_env(:jido_ai, :defaults, %{
        temperature: 1.0,
        max_tokens: 2048
      })

      on_exit(fn ->
        Application.delete_env(:jido_ai, :model_aliases)
        Application.delete_env(:jido_ai, :defaults)
      end)

      assert Config.validate() == :ok
    end

    test "returns error for invalid model spec in alias" do
      Application.put_env(:jido_ai, :model_aliases, %{
        invalid: 123
      })

      on_exit(fn -> Application.delete_env(:jido_ai, :model_aliases) end)

      assert {:error, errors} = Config.validate()
      assert length(errors) > 0
      assert Enum.any?(errors, &String.contains?(&1, "invalid"))
    end

    test "returns error for invalid temperature" do
      Application.put_env(:jido_ai, :defaults, %{
        temperature: 5.0
      })

      on_exit(fn -> Application.delete_env(:jido_ai, :defaults) end)

      assert {:error, errors} = Config.validate()
      assert Enum.any?(errors, &String.contains?(&1, "temperature"))
    end

    test "returns error for negative temperature" do
      Application.put_env(:jido_ai, :defaults, %{
        temperature: -1
      })

      on_exit(fn -> Application.delete_env(:jido_ai, :defaults) end)

      assert {:error, errors} = Config.validate()
      assert Enum.any?(errors, &String.contains?(&1, "temperature"))
    end

    test "returns error for invalid max_tokens" do
      Application.put_env(:jido_ai, :defaults, %{
        max_tokens: -100
      })

      on_exit(fn -> Application.delete_env(:jido_ai, :defaults) end)

      assert {:error, errors} = Config.validate()
      assert Enum.any?(errors, &String.contains?(&1, "max_tokens"))
    end

    test "returns error for non-integer max_tokens" do
      Application.put_env(:jido_ai, :defaults, %{
        max_tokens: "invalid"
      })

      on_exit(fn -> Application.delete_env(:jido_ai, :defaults) end)

      assert {:error, errors} = Config.validate()
      assert Enum.any?(errors, &String.contains?(&1, "max_tokens"))
    end
  end
end
