defmodule ReqLLM.Embedding do
  @moduledoc """
  Embedding functionality for ReqLLM.

  This module provides embedding generation capabilities:
  - Single text embeddings with `embed/3`
  - Batch text embeddings with `embed_many/3`

  All functions follow Vercel AI SDK patterns and return structured responses
  with proper error handling.
  """

  alias ReqLLM.Model

  # Embedding schema - shared by embed and embed_many
  @embed_opts_schema NimbleOptions.new!(
                       dimensions: [
                         type: :pos_integer,
                         doc: "Number of dimensions for embeddings"
                       ],
                       provider_options: [type: :map, doc: "Provider-specific options"]
                     )

  @doc """
  Generates embeddings for a single text input.

  ## Parameters

    * `model_spec` - Model specification in various formats:
      - String format: `"openai:text-embedding-3-small"`
      - Tuple format: `{:openai, model: "text-embedding-3-small", dimensions: 1536}`
      - Model struct: `%ReqLLM.Model{}`
    * `text` - Text to embed as a string
    * `opts` - Optional generation options

  ## Options

  #{NimbleOptions.docs(@embed_opts_schema)}

  ## Examples

      {:ok, response} = ReqLLM.Embedding.embed("openai:text-embedding-3-small", "Hello world")
      embedding = response.body.data |> List.first() |> Map.get(:embedding)
      #=> [0.1, -0.2, 0.3, ...]

      # With dimensions
      opts = [dimensions: 512]
      {:ok, response} = ReqLLM.Embedding.embed("openai:text-embedding-3-small", "Hello", opts)

  ## Return Value

  Returns `{:ok, %Req.Response{}}` on success with embedding data in the response body,
  or `{:error, reason}` on failure.
  """
  @spec embed(
          String.t() | {atom(), keyword()} | struct(),
          String.t(),
          keyword()
        ) :: {:ok, Req.Response.t()} | {:error, term()}
  def embed(model_spec, text, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @embed_opts_schema),
         {:ok, model} <- Model.from(model_spec),
         {:ok, provider_module} <- ReqLLM.provider(model.provider) do
      provider_module.embed(model, text, validated_opts)
    else
      {:error, :not_found} ->
        {:error, ReqLLM.Error.Invalid.Provider.exception(provider: "unknown")}

      error ->
        error
    end
  end

  @doc """
  Generates embeddings for multiple text inputs.

  ## Parameters

    * `model_spec` - Model specification (same formats as `embed/3`)
    * `texts` - List of texts to embed
    * `opts` - Optional generation options

  ## Options

  #{NimbleOptions.docs(@embed_opts_schema)}

  ## Examples

      texts = ["Hello world", "Goodbye world"]
      {:ok, response} = ReqLLM.Embedding.embed_many("openai:text-embedding-3-small", texts)
      embeddings = Enum.map(response.body.data, &Map.get(&1, :embedding))
      #=> [[0.1, -0.2, ...], [0.3, -0.4, ...]]

  ## Return Value

  Returns `{:ok, %Req.Response{}}` on success with embedding data in the response body,
  or `{:error, reason}` on failure.
  """
  @spec embed_many(
          String.t() | {atom(), keyword()} | struct(),
          [String.t()],
          keyword()
        ) :: {:ok, Req.Response.t()} | {:error, term()}
  def embed_many(model_spec, texts, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @embed_opts_schema),
         {:ok, model} <- Model.from(model_spec),
         {:ok, provider_module} <- ReqLLM.provider(model.provider) do
      provider_module.embed_many(model, texts, validated_opts)
    else
      {:error, :not_found} ->
        {:error, ReqLLM.Error.Invalid.Provider.exception(provider: "unknown")}

      error ->
        error
    end
  end
end
