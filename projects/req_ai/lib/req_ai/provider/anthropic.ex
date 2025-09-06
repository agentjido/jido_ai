defmodule ReqAI.Provider.Anthropic do
  @moduledoc """
  Anthropic provider implementation using the three-callback architecture.

  Provides access to Anthropic's Claude models including Claude 3.5 Sonnet and Haiku.
  Uses custom builder and parser modules for Anthropic-specific request/response formats.

  ## Usage

  Requires ANTHROPIC_API_KEY environment variable to be set.

  """

  @behaviour ReqAI.Provider

  alias ReqAI.{Model, Error}
  alias ReqAI.Request.Builder.Anthropic, as: AnthropicBuilder
  alias ReqAI.Response.Parser.Anthropic, as: AnthropicParser

  @doc """
  Returns provider information including supported models.
  """
  @impl true
  @spec provider_info() :: ReqAI.Provider.t()
  def provider_info do
    %ReqAI.Provider{
      id: :anthropic,
      name: "Anthropic",
      base_url: "https://api.anthropic.com",
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
  Generates text using the three-callback architecture.

  Uses AnthropicBuilder to create the request and AnthropicParser to extract the response.
  """
  @impl true
  @spec generate_text(Model.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def generate_text(%Model{} = model, prompt, opts \\ []) when is_binary(prompt) do
    with {:ok, request} <- build_request(model, prompt, opts),
         {:ok, response} <- send_request(request, opts),
         {:ok, text} <- parse_response(response, %{model: model}, opts) do
      {:ok, text}
    end
  end

  @doc """
  Builds a request using the Anthropic request builder.
  """
  @spec build_request(Model.t(), String.t(), keyword()) ::
          {:ok, Req.Request.t()} | {:error, Error.t()}
  def build_request(%Model{} = model, prompt, opts) do
    AnthropicBuilder.build(model, prompt, opts)
  end

  @doc """
  Sends the request using Req.
  """
  @spec send_request(Req.Request.t(), keyword()) ::
          {:ok, Req.Response.t()} | {:error, Error.t()}
  def send_request(%Req.Request{} = request, _opts) do
    case Req.post(request) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, Error.API.Request.exception(reason: "Request failed: #{inspect(reason)}")}
    end
  end

  @doc """
  Parses the response using the Anthropic response parser.
  """
  @spec parse_response(Req.Response.t(), map(), keyword()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def parse_response(%Req.Response{} = response, context, opts) do
    AnthropicParser.parse_response(response, context, opts)
  end
end
