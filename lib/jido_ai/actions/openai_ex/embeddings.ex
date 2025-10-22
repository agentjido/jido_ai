defmodule Jido.AI.Actions.OpenaiEx.Embeddings do
  @moduledoc """
  Action module for generating vector embeddings using ReqLlmBridge.

  This module supports embedding generation across all ReqLLM providers with embedding
  capabilities. Embeddings are useful for semantic search, clustering, classification,
  and other similarity-based operations.

  ## Features

  - Support for all ReqLLM providers with embedding capabilities (47+ providers)
  - Single string or batch processing of multiple strings
  - Configurable dimensions and encoding format
  - Consistent error handling and validation
  - Unified interface across all providers

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
    description: "Generate embeddings using ReqLLM with support for 47+ providers",
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
  alias Jido.AI.ReqLlmBridge
  alias Jido.AI.ReqLlmBridge.ProviderMapping
  alias ReqLLM.Provider.Generated.ValidProviders

  @doc """
  Generates embeddings for the given input using ReqLlmBridge.

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
         {:ok, input} <- validate_input(params) do
      make_reqllm_request(model, input, params)
    end
  end

  # Private functions

  @spec validate_and_get_model(map()) :: {:ok, Model.t()} | {:error, String.t()}
  defp validate_and_get_model(%{model: model}) when is_map(model) do
    case Model.from(model) do
      {:ok, model} -> validate_model_for_reqllm(model)
      error -> error
    end
  end

  defp validate_and_get_model(%{model: {provider, opts}})
       when is_atom(provider) and is_list(opts) do
    case Model.from({provider, opts}) do
      {:ok, model} -> validate_model_for_reqllm(model)
      error -> error
    end
  end

  defp validate_and_get_model(_) do
    {:error, "Invalid model specification. Must be a map or {provider, opts} tuple."}
  end

  @spec validate_model_for_reqllm(Model.t()) :: {:ok, Model.t()} | {:error, String.t()}
  defp validate_model_for_reqllm(%Model{reqllm_id: nil}) do
    {:error, "Model must have reqllm_id field for ReqLLM integration"}
  end

  defp validate_model_for_reqllm(%Model{reqllm_id: reqllm_id} = model)
       when is_binary(reqllm_id) do
    # Use provider mapping to validate the model configuration
    case ProviderMapping.validate_model_availability(reqllm_id) do
      {:ok, _config} -> {:ok, model}
      {:error, reason} -> {:error, "Model validation failed: #{reason}"}
    end
  end

  defp validate_model_for_reqllm(_) do
    {:error, "Invalid model configuration for ReqLLM"}
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

  @spec build_reqllm_options(Model.t(), map()) :: keyword()
  defp build_reqllm_options(_model, params) do
    []
    |> maybe_add_option(:dimensions, params[:dimensions])
    |> maybe_add_option(:encoding_format, params[:encoding_format])
    |> maybe_add_option(:user, params[:user])
  end

  @spec maybe_add_option(keyword(), atom(), any()) :: keyword()
  defp maybe_add_option(opts, _key, nil), do: opts
  defp maybe_add_option(opts, key, value), do: Keyword.put(opts, key, value)

  @spec make_reqllm_request(Model.t(), String.t() | [String.t()], map()) ::
          {:ok, %{embeddings: list(list(float()))}} | {:error, any()}
  defp make_reqllm_request(model, input, params) do
    Logger.debug("Making ReqLLM embedding request", module: __MODULE__)
    Logger.debug("Model: #{inspect(model.reqllm_id)}", module: __MODULE__)
    Logger.debug("Input: #{inspect(input)}", module: __MODULE__)

    # Set up API key for the model's provider
    setup_reqllm_keys(model)

    # Convert input to list format for ReqLLM.Embedding.embed/3
    input_list =
      case input do
        str when is_binary(str) -> [str]
        list when is_list(list) -> list
      end

    # Build ReqLLM options
    opts = build_reqllm_options(model, params)

    # Make ReqLLM request
    case ReqLLM.Embedding.embed(model.reqllm_id, input_list, opts) do
      {:ok, embeddings} when is_list(embeddings) ->
        # ReqLLM.Embedding.embed returns embeddings directly as a list
        {:ok, %{embeddings: embeddings}}

      {:error, error} ->
        # Map ReqLLM errors to expected format
        ReqLlmBridge.map_error({:error, error})
    end
  end

  @spec setup_reqllm_keys(Model.t()) :: :ok
  defp setup_reqllm_keys(%Model{reqllm_id: reqllm_id, api_key: api_key}) do
    # Extract provider from reqllm_id and set up environment variable
    case String.split(reqllm_id, ":", parts: 2) do
      [_provider_str, _model] ->
        # Use safe provider extraction like in openaiex.ex
        case extract_provider_from_reqllm_id(reqllm_id) do
          {:ok, provider_atom} ->
            JidoKeys.put(provider_atom, api_key)

          {:error, _reason} ->
            Logger.warning("Could not extract provider from reqllm_id: #{reqllm_id}")
        end

      _ ->
        Logger.warning("Invalid reqllm_id format: #{reqllm_id}")
    end

    :ok
  end

  @spec extract_provider_from_reqllm_id(String.t()) :: {:ok, atom()} | {:error, String.t()}
  defp extract_provider_from_reqllm_id(reqllm_id) when is_binary(reqllm_id) do
    case String.split(reqllm_id, ":", parts: 2) do
      [provider_str, _model] when provider_str != "" ->
        # Use safe string-to-atom mapping using ReqLLM's valid provider list
        valid_providers =
          ValidProviders.list()
          |> Map.new(fn atom -> {to_string(atom), atom} end)

        case Map.get(valid_providers, provider_str) do
          nil -> {:error, "Unsupported provider: #{provider_str}"}
          provider_atom -> {:ok, provider_atom}
        end

      _ ->
        {:error, "Invalid ReqLLM ID format"}
    end
  end
end
