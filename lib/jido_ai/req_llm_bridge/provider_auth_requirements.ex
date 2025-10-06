defmodule Jido.AI.ReqLlmBridge.ProviderAuthRequirements do
  @moduledoc """
  Handles provider-specific authentication requirements for ReqLLM integration.

  This module manages the unique authentication requirements of each provider,
  including special headers, API versions, multi-factor authentication, and
  validation rules, ensuring compatibility between Jido and ReqLLM systems.

  ## Key Features

  - **Provider-Specific Headers**: Manages required headers like API versions
  - **Multi-Factor Auth**: Handles providers requiring multiple auth components
  - **Validation Rules**: Provider-specific key validation logic
  - **Header Formatting**: Ensures correct header format per provider

  ## Usage

      # Get authentication requirements for a provider
      requirements = ProviderAuthRequirements.get_requirements(:anthropic)

      # Validate authentication for a provider
      :ok = ProviderAuthRequirements.validate_auth(:openai, "sk-...")

      # Get required headers for a provider
      headers = ProviderAuthRequirements.get_required_headers(:anthropic)
  """

  alias Jido.AI.Keyring

  @doc """
  Gets authentication requirements for a specific provider.

  Returns a detailed specification of what authentication components
  are required for the provider to function correctly.

  ## Parameters

    * `provider` - The provider atom

  ## Returns

    * Map containing authentication requirements

  ## Examples

      requirements = get_requirements(:anthropic)
      assert requirements.headers["anthropic-version"] == "2023-06-01"
      assert requirements.required_keys == [:anthropic_api_key]
  """
  @spec get_requirements(atom()) :: map()
  def get_requirements(:openai) do
    %{
      headers: %{},
      required_keys: [:openai_api_key],
      env_var: "OPENAI_API_KEY",
      header_format: :bearer_token,
      validation: &validate_openai_key/1,
      description: "OpenAI requires a Bearer token in Authorization header"
    }
  end

  def get_requirements(:anthropic) do
    %{
      headers: %{"anthropic-version" => "2023-06-01"},
      required_keys: [:anthropic_api_key],
      env_var: "ANTHROPIC_API_KEY",
      header_format: :api_key,
      validation: &validate_anthropic_key/1,
      description: "Anthropic requires x-api-key header and API version"
    }
  end

  def get_requirements(:google) do
    %{
      headers: %{},
      required_keys: [:google_api_key],
      env_var: "GOOGLE_API_KEY",
      header_format: :api_key,
      validation: &validate_google_key/1,
      description: "Google requires x-goog-api-key header"
    }
  end

  def get_requirements(:cloudflare) do
    %{
      headers: %{},
      required_keys: [:cloudflare_api_key],
      optional_keys: [:cloudflare_email, :cloudflare_account_id],
      env_var: "CLOUDFLARE_API_KEY",
      optional_env_vars: %{
        email: "CLOUDFLARE_EMAIL",
        account_id: "CLOUDFLARE_ACCOUNT_ID"
      },
      header_format: :api_key,
      validation: &validate_cloudflare_auth/1,
      description: "Cloudflare may require email and account ID for some operations"
    }
  end

  def get_requirements(:openrouter) do
    %{
      headers: %{},
      required_keys: [:openrouter_api_key],
      optional_keys: [:openrouter_site_url, :openrouter_site_name],
      env_var: "OPENROUTER_API_KEY",
      optional_env_vars: %{
        site_url: "OPENROUTER_SITE_URL",
        site_name: "OPENROUTER_SITE_NAME"
      },
      header_format: :bearer_token,
      validation: &validate_openrouter_key/1,
      description: "OpenRouter requires Bearer token, optionally accepts site metadata"
    }
  end

  def get_requirements(provider) do
    # Generic requirements for unknown providers
    %{
      headers: %{},
      required_keys: [:"#{provider}_api_key"],
      env_var: String.upcase("#{provider}_API_KEY"),
      header_format: :bearer_token,
      validation: &validate_generic_key/1,
      description: "Generic provider using Bearer token authentication"
    }
  end

  @doc """
  Gets required headers for a provider.

  Returns headers that must be included with every request to the provider,
  such as API version headers or additional authentication headers.

  ## Parameters

    * `provider` - The provider atom
    * `opts` - Optional parameters for dynamic headers

  ## Returns

    * Map of required headers

  ## Examples

      headers = get_required_headers(:anthropic)
      assert headers["anthropic-version"] == "2023-06-01"

      # With Cloudflare email
      headers = get_required_headers(:cloudflare, email: "user@example.com")
      assert headers["X-Auth-Email"] == "user@example.com"
  """
  @spec get_required_headers(atom(), keyword()) :: map()
  def get_required_headers(provider, opts \\ []) do
    requirements = get_requirements(provider)
    base_headers = requirements.headers || %{}

    case provider do
      :cloudflare ->
        # Add optional Cloudflare headers if available
        add_cloudflare_headers(base_headers, opts)

      :openrouter ->
        # Add optional OpenRouter headers if available
        add_openrouter_headers(base_headers, opts)

      _ ->
        base_headers
    end
  end

  @doc """
  Validates authentication for a provider.

  Performs provider-specific validation of API keys and authentication
  parameters to ensure they meet the provider's requirements.

  ## Parameters

    * `provider` - The provider atom
    * `auth_params` - Authentication parameters (key or map of params)

  ## Returns

    * `:ok` if valid
    * `{:error, reason}` if invalid

  ## Examples

      :ok = validate_auth(:openai, "sk-proj-...")
      {:error, "Invalid key format"} = validate_auth(:openai, "invalid")

      # Cloudflare with multiple params
      :ok = validate_auth(:cloudflare, %{
        api_key: "key",
        email: "user@example.com"
      })
  """
  @spec validate_auth(atom(), String.t() | map()) :: :ok | {:error, String.t()}
  def validate_auth(provider, auth_params) do
    requirements = get_requirements(provider)

    cond do
      is_binary(auth_params) ->
        # Single key validation
        requirements.validation.(auth_params)

      is_map(auth_params) ->
        # For providers with custom validation logic, use their function directly
        # Otherwise use generic multi-parameter validation
        if provider == :cloudflare do
          validate_cloudflare_auth(auth_params)
        else
          validate_auth_params(provider, auth_params, requirements)
        end

      auth_params == nil ->
        {:error, "API key is required"}

      true ->
        {:error, "Invalid authentication parameters"}
    end
  end

  @doc """
  Checks if a provider requires multi-factor authentication.

  Some providers like Cloudflare may require additional authentication
  parameters beyond just an API key.

  ## Parameters

    * `provider` - The provider atom

  ## Returns

    * `true` if provider requires multiple auth parameters
    * `false` otherwise

  ## Examples

      false = requires_multi_factor?(:openai)
      true = requires_multi_factor?(:cloudflare)
  """
  @spec requires_multi_factor?(atom()) :: boolean()
  def requires_multi_factor?(:cloudflare), do: true
  def requires_multi_factor?(_), do: false

  @doc """
  Gets optional authentication parameters for a provider.

  Returns a list of optional authentication parameters that can enhance
  the provider's functionality but are not required.

  ## Parameters

    * `provider` - The provider atom

  ## Returns

    * List of optional parameter keys

  ## Examples

      optional = get_optional_params(:openrouter)
      assert :openrouter_site_url in optional
      assert :openrouter_site_name in optional
  """
  @spec get_optional_params(atom()) :: [atom()]
  def get_optional_params(provider) do
    requirements = get_requirements(provider)
    requirements[:optional_keys] || []
  end

  @doc """
  Resolves all authentication parameters for a provider.

  Gathers required and optional authentication parameters from all sources
  including session, environment, and configuration.

  ## Parameters

    * `provider` - The provider atom
    * `opts` - Additional options
    * `session_pid` - Process ID for session lookup

  ## Returns

    * Map of all resolved authentication parameters

  ## Examples

      params = resolve_all_params(:cloudflare)
      assert params.api_key
      assert params.email  # if configured
  """
  @spec resolve_all_params(atom(), keyword(), pid()) :: map()
  def resolve_all_params(provider, opts \\ [], session_pid \\ self()) do
    requirements = get_requirements(provider)

    # Start with required keys
    params = resolve_required_params(provider, requirements, opts, session_pid)

    # Add optional parameters if available
    params = resolve_optional_params(provider, requirements, params, opts, session_pid)

    params
  end

  # Private helper functions

  defp validate_openai_key(key) when is_binary(key) do
    cond do
      String.starts_with?(key, "sk-") and byte_size(key) > 20 -> :ok
      key == "" -> {:error, "API key is empty"}
      true -> {:error, "Invalid OpenAI API key format"}
    end
  end

  defp validate_openai_key(nil) do
    {:error, "API key is required"}
  end

  defp validate_anthropic_key(key) when is_binary(key) do
    cond do
      String.starts_with?(key, "sk-ant-") and byte_size(key) > 20 -> :ok
      key == "" -> {:error, "API key is empty"}
      true -> {:error, "Invalid Anthropic API key format"}
    end
  end

  defp validate_google_key(key) when is_binary(key) do
    cond do
      byte_size(key) >= 20 -> :ok
      key == "" -> {:error, "API key is empty"}
      true -> {:error, "Invalid Google API key format"}
    end
  end

  defp validate_cloudflare_auth(auth_params) when is_map(auth_params) do
    api_key = auth_params[:api_key] || auth_params["api_key"]
    email = auth_params[:email] || auth_params["email"]

    case validate_generic_key(api_key) do
      :ok -> validate_cloudflare_email(email)
      error -> error
    end
  end

  defp validate_cloudflare_auth(key) when is_binary(key) do
    validate_generic_key(key)
  end

  defp validate_cloudflare_auth(nil) do
    {:error, "API key is required"}
  end

  # Email is optional
  defp validate_cloudflare_email(nil), do: :ok

  defp validate_cloudflare_email(email) when is_binary(email) do
    if String.contains?(email, "@") do
      :ok
    else
      {:error, "Invalid email format"}
    end
  end

  defp validate_openrouter_key(key) when is_binary(key) do
    cond do
      String.starts_with?(key, "sk-or-") and byte_size(key) > 20 -> :ok
      # Allow generic keys too
      byte_size(key) >= 20 -> :ok
      key == "" -> {:error, "API key is empty"}
      true -> {:error, "Invalid OpenRouter API key format"}
    end
  end

  defp validate_generic_key(nil), do: {:error, "API key is required"}
  defp validate_generic_key(""), do: {:error, "API key is empty"}
  defp validate_generic_key(key) when is_binary(key) and byte_size(key) > 0, do: :ok
  defp validate_generic_key(_), do: {:error, "Invalid API key format"}

  defp validate_auth_params(_provider, params, requirements) do
    # Check all required keys are present and valid
    Enum.reduce_while(requirements.required_keys, :ok, fn key, _acc ->
      value = Map.get(params, key) || Map.get(params, to_string(key))

      case requirements.validation.(value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp add_cloudflare_headers(headers, opts) do
    email = Keyword.get(opts, :email) || System.get_env("CLOUDFLARE_EMAIL")
    account_id = Keyword.get(opts, :account_id) || System.get_env("CLOUDFLARE_ACCOUNT_ID")

    headers
    |> maybe_add_header("X-Auth-Email", email)
    |> maybe_add_header("CF-Account-ID", account_id)
  end

  defp add_openrouter_headers(headers, opts) do
    site_url = Keyword.get(opts, :site_url) || System.get_env("OPENROUTER_SITE_URL")
    site_name = Keyword.get(opts, :site_name) || System.get_env("OPENROUTER_SITE_NAME")

    headers
    |> maybe_add_header("HTTP-Referer", site_url)
    |> maybe_add_header("X-Title", site_name)
  end

  defp maybe_add_header(headers, _name, nil), do: headers
  defp maybe_add_header(headers, _name, ""), do: headers
  defp maybe_add_header(headers, name, value), do: Map.put(headers, name, value)

  defp resolve_required_params(_provider, requirements, opts, session_pid) do
    Enum.reduce(requirements.required_keys, %{}, fn key, acc ->
      value =
        Keyword.get(opts, key) ||
          Keyring.get_session_value(:default, key, session_pid) ||
          Keyring.get_env_value(:default, key) ||
          System.get_env(requirements.env_var)

      if value do
        Map.put(acc, key, value)
      else
        acc
      end
    end)
  end

  defp resolve_optional_params(_provider, requirements, params, opts, session_pid) do
    optional_keys = requirements[:optional_keys] || []

    Enum.reduce(optional_keys, params, fn key, acc ->
      value =
        Keyword.get(opts, key) ||
          Keyring.get_session_value(:default, key, session_pid) ||
          Keyring.get_env_value(:default, key) ||
          get_optional_env_var(requirements, key)

      if value do
        Map.put(acc, key, value)
      else
        acc
      end
    end)
  end

  defp get_optional_env_var(requirements, key) do
    case requirements[:optional_env_vars] do
      nil ->
        nil

      env_vars ->
        # Convert key to the correct mapping
        env_key =
          case key do
            :openrouter_site_url ->
              :site_url

            :openrouter_site_name ->
              :site_name

            :cloudflare_email ->
              :email

            :cloudflare_account_id ->
              :account_id

            _ ->
              # Generic mapping: remove provider prefix
              key |> to_string() |> String.split("_", parts: 2) |> List.last() |> String.to_atom()
          end

        case Map.get(env_vars, env_key) do
          nil -> nil
          env_var -> System.get_env(env_var)
        end
    end
  end
end
