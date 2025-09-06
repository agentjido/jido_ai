defmodule ReqAI.Plugins.Kagi do
  @moduledoc """
  Req plugin that injects API keys via Kagi configuration.

  This plugin automatically reads API keys from Kagi and sets authentication 
  headers based on provider specifications passed through the request context.

  ## Usage

      # Provider info must be set in request private data
      provider_spec = %{id: :anthropic, auth: {:header, "x-api-key", :plain}}
      req = Req.new() 
            |> Req.Request.put_private(:req_ai_provider_spec, provider_spec)
            |> ReqAI.Plugins.Kagi.attach()

  ## Provider Auth Specs

  The plugin expects provider auth configuration in the format:
  `{:header, header_name, wrap_strategy}`

  Wrap strategies:
  - `:plain` - Use the API key directly
  - `:bearer` - Prefix with "Bearer "
  - Custom function - `(api_key :: String.t()) -> String.t()`

  ## Configuration

  API keys should be configured via Kagi:

      Kagi.put(:anthropic_api_key, "sk-ant-...")
      Kagi.put(:openai_api_key, "sk-...")

  """

  @doc """
  Attaches the Kagi authentication plugin to a Req request struct.

  The request must have provider specification in private data at key
  `:req_ai_provider_spec` containing at minimum `%{id: provider_id, auth: auth_spec}`.

  ## Parameters
    - `req` - The Req request struct with provider spec in private data

  ## Returns
    - Updated Req request struct with the plugin attached

  ## Examples

      provider_spec = %{id: :anthropic, auth: {:header, "x-api-key", :plain}}
      req = Req.new()
            |> Req.Request.put_private(:req_ai_provider_spec, provider_spec)
            |> ReqAI.Plugins.Kagi.attach()

  """
  @spec attach(Req.Request.t()) :: Req.Request.t()
  def attach(req) do
    Req.Request.prepend_request_steps(req, kagi_auth: &add_auth_header/1)
  end

  @doc false
  @spec add_auth_header(Req.Request.t()) :: Req.Request.t()
  def add_auth_header(req) do
    case Req.Request.get_private(req, :req_ai_provider_spec) do
      %{id: provider_id, auth: auth_spec} ->
        api_key_name = :"#{provider_id}_api_key"
        case Kagi.get(api_key_name) do
          nil ->
            req
          api_key when is_binary(api_key) ->
            apply_auth(req, auth_spec, api_key)
        end

      _ ->
        req
    end
  end

  @spec apply_auth(Req.Request.t(), tuple(), String.t()) :: Req.Request.t()
  defp apply_auth(req, {:header, header_name, wrap_strategy}, api_key) do
    header_value = wrap_api_key(api_key, wrap_strategy)
    Req.Request.put_header(req, header_name, header_value)
  end

  @spec wrap_api_key(String.t(), atom() | function()) :: String.t()
  defp wrap_api_key(api_key, :plain), do: api_key
  defp wrap_api_key(api_key, :bearer), do: "Bearer #{api_key}"
  defp wrap_api_key(api_key, wrapper_fn) when is_function(wrapper_fn, 1) do
    wrapper_fn.(api_key)
  end
end
