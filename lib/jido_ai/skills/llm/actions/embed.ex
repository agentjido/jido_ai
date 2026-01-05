defmodule Jido.AI.Skills.LLM.Actions.Embed do
  @moduledoc """
  A Jido.Action for generating text embeddings using LLM embedding models.

  This action uses ReqLLM's embedding functionality to generate vector
  embeddings for text. Embeddings can be used for semantic search,
  similarity comparison, and other NLP tasks.

  ## Parameters

  * `model` (required) - Embedding model spec (e.g., `"openai:text-embedding-3-small"`)
  * `texts` (required) - Single text string or list of texts to embed
  * `dimensions` (optional) - Output dimensions for models that support it
  * `timeout` (optional) - Request timeout in milliseconds

  ## Examples

      # Single text embedding
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.LLM.Actions.Embed, %{
        model: "openai:text-embedding-3-small",
        texts: "Hello world"
      })

      # Batch embeddings
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.LLM.Actions.Embed, %{
        model: "openai:text-embedding-3-small",
        texts: ["Hello world", "Elixir is great"]
      })

      # With dimensions
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.LLM.Actions.Embed, %{
        model: "openai:text-embedding-3-small",
        texts: "Semantic search",
        dimensions: 1536
      })

  ## Result Format

      %{
        embeddings: [[0.1, 0.2, ...], [0.3, 0.4, ...]],
        count: 2,
        model: "openai:text-embedding-3-small",
        dimensions: 1536
      }
  """

  use Jido.Action,
    name: "llm_embed",
    description: "Generate vector embeddings for text using an LLM embedding model",
    category: "ai",
    tags: ["llm", "embedding", "vectors"],
    vsn: "1.0.0",
    schema: [
      model: [
        type: :string,
        required: true,
        doc: "Embedding model spec (e.g., 'openai:text-embedding-3-small')"
      ],
      texts: [
        type: :string,
        required: false,
        doc: "Single text to embed"
      ],
      texts_list: [
        type: {:list, :string},
        required: false,
        doc: "List of texts to embed (alternative to single text)"
      ],
      dimensions: [
        type: :integer,
        required: false,
        doc: "Output dimensions for models that support it"
      ],
      timeout: [
        type: :integer,
        required: false,
        doc: "Request timeout in milliseconds"
      ]
    ]

  @doc """
  Executes the embedding action.

  ## Returns

  * `{:ok, result}` - Successful response with `embeddings`, `count`, `model`, and `dimensions` keys
  * `{:error, reason}` - Error from ReqLLM or validation
  """
  @impl Jido.Action
  def run(params, _context) do
    model = params[:model]
    texts = normalize_texts(params[:texts], params[:texts_list])
    opts = build_opts(params)

    with {:ok, response} <- ReqLLM.Embedding.embed(model, texts, opts) do
      {:ok, format_result(response, model)}
    end
  end

  # Private Functions

  defp normalize_texts(text, nil) when is_binary(text), do: [text]
  defp normalize_texts(nil, texts_list) when is_list(texts_list), do: texts_list
  defp normalize_texts(_, _), do: []

  defp build_opts(params) do
    opts = []

    opts =
      if params[:dimensions] do
        Keyword.put(opts, :dimensions, params[:dimensions])
      else
        opts
      end

    opts =
      if params[:timeout] do
        Keyword.put(opts, :receive_timeout, params[:timeout])
      else
        opts
      end

    opts
  end

  defp format_result(response, model) do
    embeddings = extract_embeddings(response)

    %{
      embeddings: embeddings,
      count: length(embeddings),
      model: model,
      dimensions: extract_dimensions(embeddings)
    }
  end

  defp extract_embeddings(%{embeddings: embeddings}) when is_list(embeddings), do: embeddings
  defp extract_embeddings(%{data: data}) when is_list(data), do: data
  defp extract_embeddings(response) when is_list(response), do: response
  defp extract_embeddings(_), do: []

  defp extract_dimensions([]), do: 0
  defp extract_dimensions([embedding | _]), do: length(embedding)
end
