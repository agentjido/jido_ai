defmodule Jido.AI.Actions.LLM.Embed do
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
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.LLM.Embed, %{
        model: "openai:text-embedding-3-small",
        texts: "Hello world"
      })

      # Batch embeddings
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.LLM.Embed, %{
        model: "openai:text-embedding-3-small",
        texts: ["Hello world", "Elixir is great"]
      })

      # With dimensions
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.LLM.Embed, %{
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
    schema:
      Zoi.object(%{
        model: Zoi.string(description: "Embedding model spec (e.g., 'openai:text-embedding-3-small')"),
        texts: Zoi.string(description: "Single text to embed") |> Zoi.optional(),
        texts_list:
          Zoi.list(Zoi.string(), description: "List of texts to embed (alternative to single text)")
          |> Zoi.optional(),
        dimensions:
          Zoi.integer(description: "Output dimensions for models that support it")
          |> Zoi.optional(),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional()
      })

  alias Jido.AI.Security

  @doc """
  Executes the embedding action.

  ## Returns

  * `{:ok, result}` - Successful response with `embeddings`, `count`, `model`, and `dimensions` keys
  * `{:error, reason}` - Error from ReqLLM or validation
  """
  @impl Jido.Action
  def run(params, _context) do
    with {:ok, _validated} <- validate_and_sanitize_params(params),
         model = params[:model],
         texts = normalize_texts(params[:texts], params[:texts_list]),
         opts = build_opts(params),
         {:ok, response} <- ReqLLM.Embedding.embed(model, texts, opts) do
      {:ok, format_result(response, model)}
    else
      {:error, reason} -> {:error, sanitize_error_for_user(reason)}
    end
  end

  # Private Functions

  defp validate_and_sanitize_params(params) do
    with {:ok, _model} <- Security.validate_string(params[:model], max_length: 1000),
         {:ok, _validated} <- validate_texts(params) do
      {:ok, params}
    else
      {:error, :empty_string} -> {:error, :model_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_texts(%{texts: text}) when is_binary(text),
    do: Security.validate_string(text, max_length: Security.max_input_length())

  defp validate_texts(%{texts_list: texts_list}) when is_list(texts_list) do
    # Validate each text in the list
    Enum.reduce_while(texts_list, {:ok, nil}, fn text, _acc ->
      case Security.validate_string(text, max_length: Security.max_input_length()) do
        {:ok, _} -> {:cont, {:ok, nil}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_texts(_params), do: {:error, :texts_required}

  defp sanitize_error_for_user(error) when is_struct(error) do
    Security.sanitize_error_message(error)
  end

  defp sanitize_error_for_user(error) when is_atom(error) do
    Security.sanitize_error_message(error)
  end

  defp sanitize_error_for_user(_error), do: "An error occurred"

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

  defp extract_embeddings(embeddings) when is_list(embeddings), do: embeddings

  defp extract_dimensions([]), do: 0
  defp extract_dimensions([embedding | _]), do: length(embedding)
end
