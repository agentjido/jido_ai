defmodule Jido.AI.Actions.OpenaiEx.Embeddings do
  @moduledoc """
  Action module for generating vector embeddings using OpenAI Ex.

  This module supports embedding generation with both OpenAI and OpenRouter providers.
  Embeddings are useful for semantic search, clustering, classification, and other
  similarity-based operations.

  ## Features

  - Support for both OpenAI and OpenRouter providers
  - Single string or batch processing of multiple strings
  - Configurable dimensions and encoding format
  - Consistent error handling and validation

  ## Usage

  ```elixir
  # Generate embeddings for a single string
  {:ok, result} = Jido.AI.Actions.OpenaiEx.Embeddings.run(
    %{
      model: %Jido.AI.Model{provider: :openai, model: "text-embedding-ada-002", api_key: "key"},
      input: "Hello, world!"
    },
    %{}
  )

  # Generate embeddings for multiple strings
  {:ok, result} = Jido.AI.Actions.OpenaiEx.Embeddings.run(
    %{
      model: %Jido.AI.Model{provider: :openai, model: "text-embedding-ada-002", api_key: "key"},
      input: ["Hello", "World"]
    },
    %{}
  )
  ```
  """
  use Jido.Action,
    name: "openai_ex_embeddings",
    description: "Generate embeddings using OpenAI Ex with support for OpenRouter",
    schema: [
      model: [
        type: {:custom, Jido.AI.Model, :validate_model_opts, []},
        required: true,
        doc:
          "The AI model to use (e.g., {:openai, [model: \"text-embedding-ada-002\"]} or %Jido.AI.Model{})"
      ],
      input: [
        type: {:or, [:string, {:list, :string}]},
        required: true,
        doc: "The text to generate embeddings for. Can be a single string or a list of strings."
      ],
      dimensions: [
        type: :integer,
        required: false,
        doc: "The number of dimensions for the embeddings (only supported by some models)"
      ],
      encoding_format: [
        type: {:in, [:float, :base64]},
        required: false,
        default: :float,
        doc: "The format to return the embeddings in"
      ]
    ]

  require Logger
  alias Jido.AI.Model
  alias OpenaiEx.Embeddings

  @valid_providers [:openai, :openrouter]

  @doc """
  Generates embeddings for the given input using OpenAI Ex.

  ## Parameters
    - params: Map containing:
      - model: Either a %Jido.AI.Model{} struct or a tuple of {provider, opts}
      - input: String or list of strings to generate embeddings for
      - dimensions: Optional number of dimensions (model dependent)
      - encoding_format: Optional format for the embeddings (:float or :base64)
    - context: The action context containing state and other information

  ## Returns
    - {:ok, %{embeddings: embeddings}} on success where embeddings is a list of vectors
    - {:error, reason} on failure
  """
  @spec run(map(), map()) :: {:ok, %{embeddings: list(list(float()))}} | {:error, String.t()}
  def run(params, context) do
    Logger.info("Running OpenAI Ex embeddings with params: #{inspect(params)}")
    Logger.info("Context: #{inspect(context)}")

    with {:ok, model} <- validate_and_get_model(params),
         {:ok, input} <- validate_input(params),
         {:ok, req} <- build_request(model, input, params) do
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

  @spec validate_input(map()) :: {:ok, String.t() | [String.t()]} | {:error, String.t()}
  defp validate_input(%{input: input}) when is_binary(input), do: {:ok, input}

  defp validate_input(%{input: inputs}) when is_list(inputs) do
    if Enum.all?(inputs, &is_binary/1) do
      {:ok, inputs}
    else
      {:error, "All inputs must be strings"}
    end
  end

  defp validate_input(_) do
    {:error, "Input must be a string or list of strings"}
  end

  @spec build_request(Model.t(), String.t() | [String.t()], map()) :: {:ok, map()}
  defp build_request(model, input, params) do
    req =
      Embeddings.new(
        model: Map.get(model, :model),
        input: input
      )

    req =
      req
      |> maybe_add_param(:dimensions, params[:dimensions])
      |> maybe_add_param(:encoding_format, params[:encoding_format])

    {:ok, req}
  end

  @spec maybe_add_param(map(), atom(), any()) :: map()
  defp maybe_add_param(req, _key, nil), do: req
  defp maybe_add_param(req, key, value), do: Map.put(req, key, value)

  @spec make_request(Model.t(), map()) ::
          {:ok, %{embeddings: list(list(float()))}} | {:error, any()}
  defp make_request(model, req) do
    client =
      OpenaiEx.new(model.api_key)
      |> maybe_add_base_url(model)
      |> maybe_add_headers(model)

    case Embeddings.create(client, req) do
      {:ok, %{data: data}} ->
        {:ok, %{embeddings: Enum.map(data, & &1.embedding)}}

      error ->
        error
    end
  end

  @spec maybe_add_base_url(OpenaiEx.t(), Model.t()) :: OpenaiEx.t()
  defp maybe_add_base_url(client, %Model{provider: :openrouter}) do
    OpenaiEx.with_base_url(client, Jido.AI.Provider.OpenRouter.base_url())
  end

  defp maybe_add_base_url(client, _), do: client

  @spec maybe_add_headers(OpenaiEx.t(), Model.t()) :: OpenaiEx.t()
  defp maybe_add_headers(client, %Model{provider: :openrouter}) do
    OpenaiEx.with_additional_headers(client, Jido.AI.Provider.OpenRouter.request_headers([]))
  end

  defp maybe_add_headers(client, _), do: client
end
