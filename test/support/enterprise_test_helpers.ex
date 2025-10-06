defmodule Jido.AI.Test.EnterpriseHelpers do
  @moduledoc """
  Test helpers for enterprise provider validation.

  Provides utilities for testing enterprise authentication patterns,
  credential validation, and environment setup for Azure OpenAI,
  Amazon Bedrock, and regional providers.
  """

  import ExUnit.Assertions
  alias Jido.AI.Keyring

  @doc """
  Skips the current test unless Azure OpenAI credentials are available.

  Checks for either API key or Microsoft Entra ID credentials.
  Should be called from within a test that has access to ExUnit.skip/1.
  """
  def skip_unless_azure_credentials do
    cond do
      azure_api_key_available?() ->
        :ok

      azure_entra_id_available?() ->
        :ok

      true ->
        throw({:skip, "Azure OpenAI credentials not available"})
    end
  end

  @doc """
  Skips the current test unless Azure Microsoft Entra ID configuration is available.
  """
  def skip_unless_azure_entra_id do
    unless azure_entra_id_available?() do
      ExUnit.skip("Azure Microsoft Entra ID configuration not available")
    end
  end

  @doc """
  Skips the current test unless AWS credentials are available.

  Checks for AWS access keys, IAM role configuration, or environment variables.
  """
  def skip_unless_aws_credentials do
    unless aws_credentials_available?() do
      ExUnit.skip("AWS credentials not available")
    end
  end

  @doc """
  Skips the current test unless AWS cross-region configuration is available.
  """
  def skip_unless_aws_cross_region do
    unless aws_cross_region_available?() do
      ExUnit.skip("AWS cross-region configuration not available")
    end
  end

  @doc """
  Skips the current test unless Alibaba Cloud credentials are available.
  """
  def skip_unless_alibaba_credentials do
    unless alibaba_credentials_available?() do
      ExUnit.skip("Alibaba Cloud credentials not available")
    end
  end

  @doc """
  Skips the current test unless regional provider configuration is available.
  """
  def skip_unless_regional_providers do
    unless regional_providers_available?() do
      ExUnit.skip("Regional provider configuration not available")
    end
  end

  @doc """
  Creates a test Azure OpenAI configuration with API key authentication.
  """
  def create_azure_api_key_config do
    case get_azure_api_key() do
      {:ok, api_key} ->
        %{
          api_key: api_key,
          endpoint: get_azure_endpoint(),
          auth_method: :api_key,
          resource_name: "test-resource"
        }

      {:error, reason} ->
        ExUnit.skip("Azure API key not available: #{reason}")
    end
  end

  @doc """
  Creates a test Azure OpenAI configuration with Microsoft Entra ID authentication.
  """
  def create_azure_entra_id_config do
    case get_azure_entra_id_config() do
      {:ok, config} ->
        Map.merge(config, %{
          endpoint: get_azure_endpoint(),
          auth_method: :entra_id
        })

      {:error, reason} ->
        ExUnit.skip("Azure Entra ID configuration not available: #{reason}")
    end
  end

  @doc """
  Creates a test AWS Bedrock configuration with IAM role authentication.
  """
  def create_aws_iam_role_config do
    case get_aws_iam_role() do
      {:ok, role_arn} ->
        %{
          role_arn: role_arn,
          region: get_aws_region(),
          auth_method: :iam_role
        }

      {:error, reason} ->
        ExUnit.skip("AWS IAM role not available: #{reason}")
    end
  end

  @doc """
  Creates a test AWS Bedrock configuration with direct credentials.
  """
  def create_aws_direct_credentials_config do
    case get_aws_direct_credentials() do
      {:ok, credentials} ->
        Map.merge(credentials, %{
          region: get_aws_region(),
          auth_method: :direct_credentials
        })

      {:error, reason} ->
        ExUnit.skip("AWS direct credentials not available: #{reason}")
    end
  end

  @doc """
  Creates a test Alibaba Cloud configuration.
  """
  def create_alibaba_cloud_config do
    case get_alibaba_cloud_credentials() do
      {:ok, credentials} ->
        Map.merge(credentials, %{
          region: get_alibaba_region(),
          endpoint: get_alibaba_endpoint(),
          compliance_level: "standard"
        })

      {:error, reason} ->
        ExUnit.skip("Alibaba Cloud credentials not available: #{reason}")
    end
  end

  @doc """
  Validates that enterprise authentication headers are properly formatted.
  """
  def assert_valid_enterprise_headers(headers, provider) do
    case provider do
      :azure_openai ->
        assert_azure_headers(headers)

      :amazon_bedrock ->
        assert_aws_headers(headers)

      :alibaba_cloud ->
        assert_alibaba_headers(headers)

      _ ->
        flunk("Unknown enterprise provider: #{provider}")
    end
  end

  @doc """
  Validates that authentication configuration is complete and valid.
  """
  def assert_valid_auth_config(config, provider) do
    case provider do
      :azure_openai ->
        assert_azure_config(config)

      :amazon_bedrock ->
        assert_aws_config(config)

      :alibaba_cloud ->
        assert_alibaba_config(config)

      _ ->
        flunk("Unknown enterprise provider: #{provider}")
    end
  end

  @doc """
  Creates a mock enterprise provider response for testing.
  """
  def create_mock_enterprise_response(provider, request_type \\ :completion) do
    base_response = %{
      id: "test-#{provider}-#{:rand.uniform(1000)}",
      object: response_object_type(request_type),
      created: :os.system_time(:second),
      model: enterprise_model_name(provider)
    }

    case request_type do
      :completion ->
        Map.merge(base_response, %{
          choices: [
            %{
              index: 0,
              message: %{
                role: "assistant",
                content: "Test response from #{provider}"
              },
              finish_reason: "stop"
            }
          ],
          usage: %{
            prompt_tokens: 10,
            completion_tokens: 5,
            total_tokens: 15
          }
        })

      :model_list ->
        %{
          object: "list",
          data: [
            %{
              id: enterprise_model_name(provider),
              object: "model",
              created: :os.system_time(:second),
              owned_by: provider_owner(provider)
            }
          ]
        }
    end
  end

  @doc """
  Measures authentication overhead for performance testing.
  """
  def measure_auth_overhead(auth_fn) do
    start_time = :os.system_time(:microsecond)
    result = auth_fn.()
    end_time = :os.system_time(:microsecond)

    overhead_ms = (end_time - start_time) / 1000

    {result, overhead_ms}
  end

  @doc """
  Validates enterprise security patterns in authentication.
  """
  def assert_enterprise_security_compliance(auth_result, security_level \\ :standard) do
    case auth_result do
      {:ok, headers} ->
        assert_security_headers(headers, security_level)

      {:error, reason} ->
        flunk("Authentication failed: #{inspect(reason)}")
    end
  end

  # Private credential checking functions

  defp azure_api_key_available? do
    case get_azure_api_key() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp azure_entra_id_available? do
    case get_azure_entra_id_config() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp aws_credentials_available? do
    aws_access_key_available?() or aws_iam_role_available?()
  end

  defp aws_access_key_available? do
    case get_aws_direct_credentials() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp aws_iam_role_available? do
    case get_aws_iam_role() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp aws_cross_region_available? do
    aws_credentials_available?() and length(get_aws_regions()) > 1
  end

  defp alibaba_credentials_available? do
    case get_alibaba_cloud_credentials() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp regional_providers_available? do
    alibaba_credentials_available?()
  end

  # Credential retrieval functions

  defp get_azure_api_key do
    case System.get_env("AZURE_OPENAI_API_KEY") || Keyring.get(:azure_openai_api_key) do
      key when is_binary(key) and byte_size(key) > 0 -> {:ok, key}
      _ -> {:error, "Azure OpenAI API key not found"}
    end
  end

  defp get_azure_endpoint do
    System.get_env("AZURE_OPENAI_ENDPOINT") ||
      Keyring.get(:azure_openai_endpoint) ||
      "https://test-resource.openai.azure.com/"
  end

  defp get_azure_entra_id_config do
    case {
      System.get_env("AZURE_TENANT_ID"),
      System.get_env("AZURE_CLIENT_ID")
    } do
      {tenant_id, client_id} when is_binary(tenant_id) and is_binary(client_id) ->
        config = %{
          tenant_id: tenant_id,
          client_id: client_id,
          client_secret: System.get_env("AZURE_CLIENT_SECRET")
        }

        {:ok, config}

      _ ->
        {:error, "Azure Entra ID configuration not found"}
    end
  end

  defp get_aws_direct_credentials do
    case {
      System.get_env("AWS_ACCESS_KEY_ID"),
      System.get_env("AWS_SECRET_ACCESS_KEY")
    } do
      {access_key_id, secret_access_key}
      when is_binary(access_key_id) and is_binary(secret_access_key) ->
        credentials = %{
          access_key_id: access_key_id,
          secret_access_key: secret_access_key,
          session_token: System.get_env("AWS_SESSION_TOKEN")
        }

        {:ok, credentials}

      _ ->
        {:error, "AWS credentials not found"}
    end
  end

  defp get_aws_iam_role do
    case System.get_env("AWS_ROLE_ARN") do
      role_arn when is_binary(role_arn) -> {:ok, role_arn}
      _ -> {:error, "AWS IAM role not found"}
    end
  end

  defp get_aws_region do
    System.get_env("AWS_REGION") || "us-east-1"
  end

  defp get_aws_regions do
    (System.get_env("AWS_TEST_REGIONS") || "us-east-1,us-west-2")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end

  defp get_alibaba_cloud_credentials do
    case System.get_env("ALIBABA_CLOUD_API_KEY") do
      api_key when is_binary(api_key) ->
        credentials = %{
          api_key: api_key,
          workspace: System.get_env("ALIBABA_CLOUD_WORKSPACE") || "default"
        }

        {:ok, credentials}

      _ ->
        {:error, "Alibaba Cloud credentials not found"}
    end
  end

  defp get_alibaba_region do
    System.get_env("ALIBABA_CLOUD_REGION") || "ap-southeast-1"
  end

  defp get_alibaba_endpoint do
    System.get_env("ALIBABA_CLOUD_ENDPOINT") || "https://dashscope.aliyuncs.com"
  end

  # Header validation functions

  defp assert_azure_headers(headers) do
    headers_map = Enum.into(headers, %{})

    assert Map.has_key?(headers_map, "api-key") or Map.has_key?(headers_map, "Authorization"),
           "Azure headers must include either api-key or Authorization"

    assert Map.get(headers_map, "Content-Type") == "application/json",
           "Azure headers must include Content-Type: application/json"
  end

  defp assert_aws_headers(headers) do
    headers_map = Enum.into(headers, %{})

    assert Map.has_key?(headers_map, "Authorization"),
           "AWS headers must include Authorization"

    assert Map.has_key?(headers_map, "X-Amz-Date"),
           "AWS headers must include X-Amz-Date"

    assert String.starts_with?(headers_map["Authorization"], "AWS4-HMAC-SHA256"),
           "AWS Authorization header must use Signature Version 4"
  end

  defp assert_alibaba_headers(headers) do
    headers_map = Enum.into(headers, %{})

    assert Map.has_key?(headers_map, "Authorization"),
           "Alibaba headers must include Authorization"

    assert String.starts_with?(headers_map["Authorization"], "Bearer "),
           "Alibaba Authorization header must be Bearer token"
  end

  # Configuration validation functions

  defp assert_azure_config(config) do
    assert Map.has_key?(config, :endpoint), "Azure config must include endpoint"
    assert Map.has_key?(config, :auth_method), "Azure config must include auth_method"

    case config.auth_method do
      :api_key ->
        assert Map.has_key?(config, :api_key), "Azure API key config must include api_key"

      :entra_id ->
        assert Map.has_key?(config, :tenant_id), "Azure Entra ID config must include tenant_id"
        assert Map.has_key?(config, :client_id), "Azure Entra ID config must include client_id"

      _ ->
        flunk("Unknown Azure auth method: #{config.auth_method}")
    end
  end

  defp assert_aws_config(config) do
    assert Map.has_key?(config, :region), "AWS config must include region"
    assert Map.has_key?(config, :auth_method), "AWS config must include auth_method"

    case config.auth_method do
      :iam_role ->
        assert Map.has_key?(config, :role_arn), "AWS IAM role config must include role_arn"

      :direct_credentials ->
        assert Map.has_key?(config, :access_key_id),
               "AWS direct credentials config must include access_key_id"

        assert Map.has_key?(config, :secret_access_key),
               "AWS direct credentials config must include secret_access_key"

      _ ->
        flunk("Unknown AWS auth method: #{config.auth_method}")
    end
  end

  defp assert_alibaba_config(config) do
    assert Map.has_key?(config, :region), "Alibaba config must include region"
    assert Map.has_key?(config, :endpoint), "Alibaba config must include endpoint"
    assert Map.has_key?(config, :api_key), "Alibaba config must include api_key"
  end

  # Mock response helpers

  defp response_object_type(:completion), do: "chat.completion"
  defp response_object_type(:model_list), do: "list"

  defp enterprise_model_name(:azure_openai), do: "gpt-4"
  defp enterprise_model_name(:amazon_bedrock), do: "anthropic.claude-3-sonnet-20240229-v1:0"
  defp enterprise_model_name(:alibaba_cloud), do: "qwen2.5-72b-instruct"

  defp provider_owner(:azure_openai), do: "microsoft"
  defp provider_owner(:amazon_bedrock), do: "amazon"
  defp provider_owner(:alibaba_cloud), do: "alibaba"

  # Security validation functions

  defp assert_security_headers(headers, security_level) do
    headers_map = Enum.into(headers, %{})

    # Basic security requirements
    assert Map.has_key?(headers_map, "Content-Type"),
           "Security headers must include Content-Type"

    case security_level do
      :standard ->
        assert Map.has_key?(headers_map, "Authorization") or Map.has_key?(headers_map, "api-key"),
               "Standard security requires authentication header"

      :enterprise ->
        assert Map.has_key?(headers_map, "Authorization"),
               "Enterprise security requires Authorization header"

        # Additional enterprise security checks could be added here
        :ok

      :compliance ->
        assert Map.has_key?(headers_map, "Authorization"),
               "Compliance security requires Authorization header"

        # Additional compliance checks could be added here
        :ok
    end
  end
end
