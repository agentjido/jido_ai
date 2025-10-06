defmodule Jido.AI.ReqLlmBridge.ProviderAuthRequirementsTest do
  use ExUnit.Case, async: true
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.Keyring
  alias Jido.AI.ReqLlmBridge.ProviderAuthRequirements

  setup :set_mimic_global

  setup do
    Mimic.copy(System)
    Mimic.copy(Keyring)
    :ok
  end

  describe "get_requirements/1 - provider requirements" do
    test "returns OpenAI requirements" do
      requirements = ProviderAuthRequirements.get_requirements(:openai)

      assert requirements.required_keys == [:openai_api_key]
      assert requirements.env_var == "OPENAI_API_KEY"
      assert requirements.header_format == :bearer_token
      assert is_function(requirements.validation, 1)
    end

    test "returns Anthropic requirements with version header" do
      requirements = ProviderAuthRequirements.get_requirements(:anthropic)

      assert requirements.required_keys == [:anthropic_api_key]
      assert requirements.env_var == "ANTHROPIC_API_KEY"
      assert requirements.header_format == :api_key
      assert requirements.headers["anthropic-version"] == "2023-06-01"
      assert is_function(requirements.validation, 1)
    end

    test "returns Google requirements" do
      requirements = ProviderAuthRequirements.get_requirements(:google)

      assert requirements.required_keys == [:google_api_key]
      assert requirements.env_var == "GOOGLE_API_KEY"
      assert requirements.header_format == :api_key
      assert is_function(requirements.validation, 1)
    end

    test "returns Cloudflare requirements with optional fields" do
      requirements = ProviderAuthRequirements.get_requirements(:cloudflare)

      assert requirements.required_keys == [:cloudflare_api_key]
      assert requirements.optional_keys == [:cloudflare_email, :cloudflare_account_id]
      assert requirements.env_var == "CLOUDFLARE_API_KEY"
      assert requirements.optional_env_vars.email == "CLOUDFLARE_EMAIL"
      assert requirements.optional_env_vars.account_id == "CLOUDFLARE_ACCOUNT_ID"
    end

    test "returns OpenRouter requirements with optional metadata" do
      requirements = ProviderAuthRequirements.get_requirements(:openrouter)

      assert requirements.required_keys == [:openrouter_api_key]
      assert requirements.optional_keys == [:openrouter_site_url, :openrouter_site_name]
      assert requirements.env_var == "OPENROUTER_API_KEY"
      assert requirements.header_format == :bearer_token
    end

    test "returns generic requirements for unknown provider" do
      requirements = ProviderAuthRequirements.get_requirements(:unknown)

      assert requirements.required_keys == [:unknown_api_key]
      assert requirements.env_var == "UNKNOWN_API_KEY"
      assert requirements.header_format == :bearer_token
      assert is_function(requirements.validation, 1)
    end
  end

  describe "get_required_headers/2 - provider headers" do
    test "returns Anthropic version header" do
      headers = ProviderAuthRequirements.get_required_headers(:anthropic)
      assert headers["anthropic-version"] == "2023-06-01"
    end

    test "returns empty headers for OpenAI" do
      headers = ProviderAuthRequirements.get_required_headers(:openai)
      assert headers == %{}
    end

    test "adds Cloudflare email header when provided" do
      stub(System, :get_env, fn
        "CLOUDFLARE_EMAIL" -> nil
        _ -> nil
      end)

      headers =
        ProviderAuthRequirements.get_required_headers(
          :cloudflare,
          email: "user@example.com"
        )

      assert headers["X-Auth-Email"] == "user@example.com"
    end

    test "adds Cloudflare account ID from environment" do
      stub(System, :get_env, fn
        "CLOUDFLARE_ACCOUNT_ID" -> "account-123"
        _ -> nil
      end)

      headers = ProviderAuthRequirements.get_required_headers(:cloudflare)
      assert headers["CF-Account-ID"] == "account-123"
    end

    test "adds OpenRouter metadata headers" do
      headers =
        ProviderAuthRequirements.get_required_headers(
          :openrouter,
          site_url: "https://example.com",
          site_name: "Example App"
        )

      assert headers["HTTP-Referer"] == "https://example.com"
      assert headers["X-Title"] == "Example App"
    end
  end

  describe "validate_auth/2 - authentication validation" do
    test "validates OpenAI key format" do
      assert :ok = ProviderAuthRequirements.validate_auth(:openai, "sk-proj-abcdef123456789")
      assert {:error, _} = ProviderAuthRequirements.validate_auth(:openai, "invalid")
      assert {:error, "API key is empty"} = ProviderAuthRequirements.validate_auth(:openai, "")
    end

    test "validates Anthropic key format" do
      assert :ok = ProviderAuthRequirements.validate_auth(:anthropic, "sk-ant-abcdef123456789012")
      assert {:error, _} = ProviderAuthRequirements.validate_auth(:anthropic, "sk-wrong-format")
      assert {:error, "API key is empty"} = ProviderAuthRequirements.validate_auth(:anthropic, "")
    end

    test "validates Google key format" do
      assert :ok = ProviderAuthRequirements.validate_auth(:google, "AIzaSyD-abcdef123456789")
      assert {:error, _} = ProviderAuthRequirements.validate_auth(:google, "short")
      assert {:error, "API key is empty"} = ProviderAuthRequirements.validate_auth(:google, "")
    end

    test "validates Cloudflare with just key" do
      assert :ok = ProviderAuthRequirements.validate_auth(:cloudflare, "cf-key-123456789")
      assert {:error, _} = ProviderAuthRequirements.validate_auth(:cloudflare, "")
    end

    test "validates Cloudflare with key and email" do
      auth_params = %{
        api_key: "cf-key-123456789",
        email: "user@example.com"
      }

      assert :ok = ProviderAuthRequirements.validate_auth(:cloudflare, auth_params)
    end

    test "validates Cloudflare rejects invalid email" do
      auth_params = %{
        api_key: "cf-key-123456789",
        email: "not-an-email"
      }

      assert {:error, "Invalid email format"} =
               ProviderAuthRequirements.validate_auth(:cloudflare, auth_params)
    end

    test "validates OpenRouter key format" do
      assert :ok = ProviderAuthRequirements.validate_auth(:openrouter, "sk-or-v1-abcdef123456")

      assert :ok =
               ProviderAuthRequirements.validate_auth(:openrouter, "generic-key-with-20-chars")

      assert {:error, _} = ProviderAuthRequirements.validate_auth(:openrouter, "short")
    end

    test "validates generic provider key" do
      assert :ok = ProviderAuthRequirements.validate_auth(:unknown, "any-non-empty-key")
      assert {:error, "API key is empty"} = ProviderAuthRequirements.validate_auth(:unknown, "")
      assert {:error, _} = ProviderAuthRequirements.validate_auth(:unknown, nil)
    end
  end

  describe "requires_multi_factor?/1 - multi-factor check" do
    test "returns true for Cloudflare" do
      assert ProviderAuthRequirements.requires_multi_factor?(:cloudflare)
    end

    test "returns false for single-key providers" do
      refute ProviderAuthRequirements.requires_multi_factor?(:openai)
      refute ProviderAuthRequirements.requires_multi_factor?(:anthropic)
      refute ProviderAuthRequirements.requires_multi_factor?(:google)
      refute ProviderAuthRequirements.requires_multi_factor?(:openrouter)
    end
  end

  describe "get_optional_params/1 - optional parameters" do
    test "returns empty list for providers without optional params" do
      assert ProviderAuthRequirements.get_optional_params(:openai) == []
      assert ProviderAuthRequirements.get_optional_params(:anthropic) == []
      assert ProviderAuthRequirements.get_optional_params(:google) == []
    end

    test "returns optional params for Cloudflare" do
      optional = ProviderAuthRequirements.get_optional_params(:cloudflare)
      assert :cloudflare_email in optional
      assert :cloudflare_account_id in optional
    end

    test "returns optional params for OpenRouter" do
      optional = ProviderAuthRequirements.get_optional_params(:openrouter)
      assert :openrouter_site_url in optional
      assert :openrouter_site_name in optional
    end
  end

  describe "resolve_all_params/3 - parameter resolution" do
    test "resolves required parameters from options" do
      params =
        ProviderAuthRequirements.resolve_all_params(
          :openai,
          openai_api_key: "from-options"
        )

      assert params.openai_api_key == "from-options"
    end

    test "resolves required parameters from session" do
      stub(Keyring, :get_session_value, fn
        :default, :openai_api_key, _ -> "from-session"
        :default, _, _ -> nil
      end)

      params = ProviderAuthRequirements.resolve_all_params(:openai)
      assert params.openai_api_key == "from-session"
    end

    test "resolves required parameters from environment" do
      stub(Keyring, :get_session_value, fn :default, _, _ -> nil end)

      stub(Keyring, :get_env_value, fn
        :default, :openai_api_key -> "from-keyring-env"
        :default, _ -> nil
      end)

      params = ProviderAuthRequirements.resolve_all_params(:openai)
      assert params.openai_api_key == "from-keyring-env"
    end

    test "resolves optional parameters for Cloudflare" do
      stub(Keyring, :get_session_value, fn
        :default, :cloudflare_api_key, _ -> "cf-key"
        :default, :cloudflare_email, _ -> "user@example.com"
        :default, _, _ -> nil
      end)

      stub(Keyring, :get_env_value, fn
        :default, _ -> nil
      end)

      params = ProviderAuthRequirements.resolve_all_params(:cloudflare)
      assert params.cloudflare_api_key == "cf-key"
      assert params.cloudflare_email == "user@example.com"
    end

    test "resolves optional parameters from environment" do
      stub(Keyring, :get_session_value, fn :default, _, _ -> nil end)

      stub(Keyring, :get_env_value, fn
        :default, :openrouter_api_key -> "or-key"
        :default, _ -> nil
      end)

      stub(System, :get_env, fn
        "OPENROUTER_SITE_URL" -> "https://example.com"
        "OPENROUTER_SITE_NAME" -> "Example"
        _ -> nil
      end)

      params = ProviderAuthRequirements.resolve_all_params(:openrouter)
      assert params.openrouter_api_key == "or-key"
      assert params.openrouter_site_url == "https://example.com"
      assert params.openrouter_site_name == "Example"
    end

    test "options override other sources" do
      stub(Keyring, :get_session_value, fn
        :default, :openai_api_key, _ -> "from-session"
        :default, _, _ -> nil
      end)

      params =
        ProviderAuthRequirements.resolve_all_params(
          :openai,
          openai_api_key: "from-options"
        )

      assert params.openai_api_key == "from-options"
    end
  end

  describe "edge cases and error handling" do
    test "handles nil authentication parameters" do
      assert {:error, "API key is required"} =
               ProviderAuthRequirements.validate_auth(:openai, nil)
    end

    test "handles invalid parameter types" do
      assert {:error, "Invalid authentication parameters"} =
               ProviderAuthRequirements.validate_auth(:openai, 123)

      assert {:error, "Invalid authentication parameters"} =
               ProviderAuthRequirements.validate_auth(:openai, [])
    end

    test "handles empty map authentication" do
      assert {:error, _} =
               ProviderAuthRequirements.validate_auth(:openai, %{})
    end

    test "handles string keys in authentication map" do
      auth_params = %{
        "api_key" => "sk-test-key",
        "email" => "user@example.com"
      }

      assert :ok = ProviderAuthRequirements.validate_auth(:cloudflare, auth_params)
    end
  end
end
