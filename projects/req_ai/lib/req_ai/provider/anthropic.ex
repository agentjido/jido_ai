defmodule ReqAI.Provider.Anthropic do
  @moduledoc """
  Anthropic provider implementation for text generation using Claude models.

  Provides access to Anthropic's Claude models including Claude 3.5 Sonnet and Haiku.

  ## Usage

  Requires ANTHROPIC_API_KEY environment variable to be set.

  """

  @behaviour ReqAI.Provider

  alias ReqAI.{Model, Error}

  @base_url "https://api.anthropic.com/v1/messages"

  @doc """
  Returns provider information including supported models.
  """
  @impl true
  @spec provider_info() :: ReqAI.Provider.t()
  def provider_info do
    %ReqAI.Provider{
      id: :anthropic,
      name: "Anthropic",
      base_url: @base_url,
      models: %{
        "claude-3-5-sonnet-20241022" => %{
          name: "Claude 3.5 Sonnet",
          limit: %{context: 200_000, output: 8192}
        },
        "claude-3-5-haiku-20241022" => %{
          name: "Claude 3.5 Haiku", 
          limit: %{context: 200_000, output: 8192}
        },
        "claude-3-opus-20240229" => %{
          name: "Claude 3 Opus",
          limit: %{context: 200_000, output: 4096}
        }
      }
    }
  end

  @doc """
  Generates text using the Anthropic Claude API.
  """
  @impl true
  @spec generate_text(Model.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def generate_text(%Model{} = model, prompt, opts \\ []) when is_binary(prompt) do
    api_key = get_api_key()
    
    if is_nil(api_key) do
      {:error, Error.Invalid.Parameter.exception(parameter: "ANTHROPIC_API_KEY environment variable")}
    else
      body = build_request_body(model, prompt, opts)
      headers = build_headers(api_key)
      
      case Req.post(@base_url, json: body, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          extract_text_response(response)
          
        {:ok, %{status: status, body: error_body}} ->
          {:error, Error.API.Request.exception(status: status, reason: format_error(error_body))}
          
        {:error, reason} ->
          {:error, Error.API.Request.exception(reason: "Request failed: #{inspect(reason)}")}
      end
    end
  end

  defp get_api_key do
    System.get_env("ANTHROPIC_API_KEY") || Application.get_env(:req_ai, :anthropic_api_key)
  end

  defp build_request_body(%Model{} = model, prompt, opts) do
    %{
      model: model.model,
      messages: [%{role: "user", content: prompt}],
      max_tokens: model.max_tokens || 4096
    }
    |> maybe_add_temperature(model.temperature)
    |> maybe_add_system_prompt(Keyword.get(opts, :system_prompt))
  end

  defp maybe_add_temperature(body, nil), do: body
  defp maybe_add_temperature(body, temp), do: Map.put(body, :temperature, temp)

  defp maybe_add_system_prompt(body, nil), do: body
  defp maybe_add_system_prompt(body, system), do: Map.put(body, :system, system)

  defp build_headers(api_key) do
    [
      {"content-type", "application/json"},
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"}
    ]
  end

  defp extract_text_response(%{"content" => [%{"text" => text} | _]}) do
    {:ok, text}
  end

  defp extract_text_response(%{"content" => content}) when is_list(content) do
    text = 
      content
      |> Enum.filter(&(Map.get(&1, "type") == "text"))
      |> Enum.map(&Map.get(&1, "text", ""))
      |> Enum.join("")
    
    {:ok, text}
  end

  defp extract_text_response(response) do
    {:error, Error.API.Request.exception(reason: "Unexpected response format: #{inspect(response)}")}
  end

  defp format_error(%{"error" => %{"message" => message}}), do: message
  defp format_error(%{"error" => error}) when is_map(error), do: inspect(error)
  defp format_error(error), do: inspect(error)
end
