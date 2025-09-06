defmodule ReqAI.Request.Builder.Anthropic do
  @moduledoc """
  Request builder for Anthropic Claude API.

  Builds proper Anthropic /v1/messages requests with required headers and body format.
  Converts simple prompts to Anthropic's message format and handles API authentication.
  """

  alias ReqAI.{Config, Error}

  @doc """
  Builds a Req.Request for the Anthropic Claude API.

  Creates a properly formatted request with:
  - Required Anthropic headers (x-api-key, anthropic-version, content-type)
  - Message format conversion (string prompt -> messages array)
  - Model parameters (temperature, max_tokens)

  ## Parameters

  - `model` - ReqAI.Model struct with provider, model name, and parameters
  - `prompt` - String prompt to convert to messages format
  - `opts` - Additional options (system_prompt, etc.)

  ## Examples

      model = ReqAI.Model.new(:anthropic, "claude-3-5-sonnet-20241022", max_tokens: 1000)
      {:ok, request} = ReqAI.Request.Builder.Anthropic.build(model, "Hello", [])
      
      # With system prompt
      opts = [system_prompt: "You are a helpful assistant"]
      {:ok, request} = ReqAI.Request.Builder.Anthropic.build(model, "Hello", opts)

  """
  @spec build(ReqAI.Model.t(), String.t(), keyword()) ::
          {:ok, Req.Request.t()} | {:error, ReqAI.Error.t()}
  def build(%ReqAI.Model{} = model, prompt, opts \\ []) when is_binary(prompt) do
    case Config.api_key(:anthropic) do
      nil ->
        {:error,
         Error.Invalid.Parameter.exception(parameter: "ANTHROPIC_API_KEY environment variable")}

      api_key ->
        request =
          Req.new(
            base_url: "https://api.anthropic.com/v1/messages",
            headers: build_headers(api_key),
            json: build_body(model, prompt, opts)
          )

        {:ok, request}
    end
  end

  defp build_headers(api_key) do
    [
      {"content-type", "application/json"},
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"}
    ]
  end

  defp build_body(%ReqAI.Model{} = model, prompt, opts) do
    body = %{
      model: model.model,
      messages: [%{role: "user", content: prompt}],
      max_tokens: model.max_tokens || 4096
    }

    body
    |> maybe_add_temperature(model.temperature)
    |> maybe_add_system_prompt(Keyword.get(opts, :system_prompt))
  end

  defp maybe_add_temperature(body, nil), do: body
  defp maybe_add_temperature(body, temp), do: Map.put(body, :temperature, temp)

  defp maybe_add_system_prompt(body, nil), do: body
  defp maybe_add_system_prompt(body, system), do: Map.put(body, :system, system)
end
