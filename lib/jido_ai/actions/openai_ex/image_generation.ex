defmodule Jido.AI.Actions.OpenaiEx.ImageGeneration do
  @moduledoc """
  Action module for generating images using OpenAI Ex.

  This module supports image generation with both OpenAI and OpenRouter providers.
  It uses the DALL-E models to create images from text prompts with various
  customization options.

  ## Features

  - Support for both OpenAI and OpenRouter providers
  - Customizable image generation parameters (size, quality, style)
  - Multiple image generation in a single request
  - Support for different response formats (URL or base64)
  - Consistent error handling and validation

  ## Usage

  ```elixir
  # Generate a single image
  {:ok, result} = Jido.AI.Actions.OpenaiEx.ImageGeneration.run(
    %{
      model: %Jido.AI.Model{provider: :openai, model: "dall-e-3", api_key: "key"},
      prompt: "A beautiful sunset over the ocean"
    },
    %{}
  )

  # Generate multiple images with custom parameters
  {:ok, result} = Jido.AI.Actions.OpenaiEx.ImageGeneration.run(
    %{
      model: %Jido.AI.Model{provider: :openai, model: "dall-e-3", api_key: "key"},
      prompt: "A beautiful sunset over the ocean",
      n: 2,
      size: "1024x1792",
      quality: "hd",
      style: "natural"
    },
    %{}
  )
  ```
  """
  use Jido.Action,
    name: "openai_ex_image_generation",
    description: "Generate images using OpenAI Ex with support for OpenRouter",
    schema: [
      model: [
        type: {:custom, Jido.AI.Model, :validate_model_opts, []},
        required: true,
        doc: "The AI model to use (e.g., {:openai, [model: \"dall-e-3\"]} or %Jido.AI.Model{})"
      ],
      prompt: [
        type: :string,
        required: true,
        doc: "The text prompt to generate images from"
      ],
      n: [
        type: :integer,
        required: false,
        default: 1,
        doc: "Number of images to generate (1-10)"
      ],
      size: [
        type: {:in, ["1024x1024", "1024x1792", "1792x1024"]},
        required: false,
        default: "1024x1024",
        doc: "Size of the generated images"
      ],
      quality: [
        type: {:in, ["standard", "hd"]},
        required: false,
        default: "standard",
        doc: "Quality of the generated images"
      ],
      style: [
        type: {:in, ["vivid", "natural"]},
        required: false,
        default: "vivid",
        doc: "Style of the generated images"
      ],
      response_format: [
        type: {:in, ["url", "b64_json"]},
        required: false,
        default: "url",
        doc: "Format of the response"
      ]
    ]

  require Logger
  alias Jido.AI.Model
  alias OpenaiEx.Images

  @valid_providers [:openai, :openrouter, :google]

  @doc """
  Generates images from a text prompt using OpenAI Ex.

  ## Parameters
    - params: Map containing:
      - model: Either a %Jido.AI.Model{} struct or a tuple of {provider, opts}
      - prompt: Text description of the desired image
      - n: Optional number of images to generate (1-10)
      - size: Optional size of the generated images
      - quality: Optional quality level ("standard" or "hd")
      - style: Optional style ("vivid" or "natural")
      - response_format: Optional format ("url" or "b64_json")
    - context: The action context containing state and other information

  ## Returns
    - {:ok, %{images: images}} on success where images is a list of URLs or base64 strings
    - {:error, reason} on failure
  """
  @spec run(map(), map()) :: {:ok, %{images: list(String.t())}} | {:error, String.t()}
  def run(params, context) do
    Logger.info("Running OpenAI Ex image generation with params: #{inspect(params)}")
    Logger.info("Context: #{inspect(context)}")

    with {:ok, model} <- validate_and_get_model(params),
         {:ok, prompt} <- validate_prompt(params),
         {:ok, req} <- build_request(model, prompt, params) do
      make_request(model, req)
    end
  end

  # Private functions

  @spec validate_and_get_model(map()) :: {:ok, Model.t()} | {:error, String.t()}
  defp validate_and_get_model(%{model: model}) when is_map(model) do
    case Model.from(model) do
      {:ok, model} -> validate_provider(model)
      error -> error
    end
  end

  defp validate_and_get_model(%{model: {provider, opts}})
       when is_atom(provider) and is_list(opts) do
    case Model.from({provider, opts}) do
      {:ok, model} -> validate_provider(model)
      error -> error
    end
  end

  defp validate_and_get_model(_) do
    {:error, "Invalid model specification. Must be a map or {provider, opts} tuple."}
  end

  @spec validate_provider(Model.t()) :: {:ok, Model.t()} | {:error, String.t()}
  defp validate_provider(%Model{provider: provider} = model) when provider in @valid_providers do
    {:ok, model}
  end

  defp validate_provider(%Model{provider: provider}) do
    {:error,
     "Invalid provider: #{inspect(provider)}. Must be one of: #{inspect(@valid_providers)}"}
  end

  @spec validate_prompt(map()) :: {:ok, String.t()} | {:error, String.t()}
  defp validate_prompt(%{prompt: prompt}) when is_binary(prompt) and byte_size(prompt) > 0,
    do: {:ok, prompt}

  defp validate_prompt(%{prompt: _}), do: {:error, "Prompt must be a non-empty string"}
  defp validate_prompt(_), do: {:error, "Prompt is required"}

  @spec build_request(Model.t(), String.t(), map()) :: {:ok, map()}
  defp build_request(model, prompt, params) do
    req =
      Images.Generate.new(
        model: Map.get(model, :model),
        prompt: prompt
      )

    req =
      req
      |> maybe_add_param(:n, params[:n])
      |> maybe_add_param(:size, params[:size])
      |> maybe_add_param(:quality, params[:quality])
      |> maybe_add_param(:style, params[:style])
      |> maybe_add_param(:response_format, params[:response_format])

    {:ok, req}
  end

  @spec maybe_add_param(map(), atom(), any()) :: map()
  defp maybe_add_param(req, _key, nil), do: req
  defp maybe_add_param(req, key, value), do: Map.put(req, key, value)

  @spec make_request(Model.t(), map()) :: {:ok, %{images: list(String.t())}} | {:error, any()}
  defp make_request(model, req) do
    client =
      OpenaiEx.new(model.api_key)
      |> maybe_add_base_url(model)
      |> maybe_add_headers(model)

    case Images.generate(client, req) do
      {:ok, %{data: data}} ->
        {:ok, %{images: Enum.map(data, &extract_image/1)}}

      error ->
        error
    end
  end

  @spec extract_image(map()) :: String.t() | nil
  defp extract_image(%{url: url}) when not is_nil(url), do: url
  defp extract_image(%{b64_json: b64}) when not is_nil(b64), do: b64
  defp extract_image(_), do: nil

  @spec maybe_add_base_url(OpenaiEx.t(), Model.t()) :: OpenaiEx.t()
  defp maybe_add_base_url(client, %Model{provider: :openrouter}) do
    OpenaiEx.with_base_url(client, Jido.AI.Provider.OpenRouter.base_url())
  end

  defp maybe_add_base_url(client, %Model{provider: :google}) do
    OpenaiEx.with_base_url(client, Jido.AI.Provider.Google.base_url())
  end

  defp maybe_add_base_url(client, _), do: client

  @spec maybe_add_headers(OpenaiEx.t(), Model.t()) :: OpenaiEx.t()
  defp maybe_add_headers(client, %Model{provider: :openrouter}) do
    OpenaiEx.with_additional_headers(client, Jido.AI.Provider.OpenRouter.request_headers([]))
  end

  defp maybe_add_headers(client, %Model{provider: :google}) do
    OpenaiEx.with_additional_headers(client, Jido.AI.Provider.Google.request_headers([]))
  end

  defp maybe_add_headers(client, _), do: client
end
