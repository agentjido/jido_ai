defmodule Jido.AI.Actions.LLM.Embed do
  @moduledoc """
  A Jido.Action for generating text embeddings using LLM embedding models.

  This action uses ReqLLM's embedding functionality to generate vector
  embeddings for text. Embeddings can be used for semantic search,
  similarity comparison, and other NLP tasks.

  ## Parameters

  * `model` (optional) - Model alias (e.g., `:embedding`) or direct model spec (default: `:embedding`)
  * `texts` (optional) - Single text string to embed
  * `texts_list` (optional) - List of texts to embed
  * `dimensions` (optional) - Output dimensions for models that support it
  * `timeout` (optional) - Request timeout in milliseconds

  Provide either `texts` or `texts_list`.

  ## Examples

      # Single text embedding
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.LLM.Embed, %{
        texts: "Hello world"
      })

      # Batch embeddings
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.LLM.Embed, %{
        texts_list: ["Hello world", "Elixir is great"]
      })

      # With dimensions
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.LLM.Embed, %{
        model: :embedding,
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
        model:
          Zoi.any(description: "Model alias (e.g., :embedding) or direct model spec string")
          |> Zoi.optional(),
        texts: Zoi.string(description: "Single text to embed") |> Zoi.optional(),
        texts_list:
          Zoi.list(Zoi.string(), description: "List of texts to embed (alternative to single text)")
          |> Zoi.optional(),
        dimensions:
          Zoi.integer(description: "Output dimensions for models that support it")
          |> Zoi.optional(),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional()
      })

  alias Jido.AI.Actions.Helpers
  alias Jido.AI.Error.Sanitize
  alias Jido.AI.Validation

  @doc """
  Executes the embedding action.

  ## Returns

  * `{:ok, result}` - Successful response with `embeddings`, `count`, `model`, and `dimensions` keys
  * `{:error, reason}` - Error from ReqLLM or validation
  """
  @impl Jido.Action
  def run(params, context) do
    params = apply_context_defaults(params, context)

    with {:ok, _validated} <- validate_and_sanitize_params(params),
         {:ok, model} <- Helpers.resolve_model(params[:model], :embedding),
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
    with {:ok, _validated} <- validate_texts(params) do
      {:ok, params}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_texts(%{texts: text}) when is_binary(text),
    do: Validation.validate_string(text, max_length: Validation.max_input_length())

  defp validate_texts(%{texts_list: texts_list}) when is_list(texts_list) do
    # Validate each text in the list
    Enum.reduce_while(texts_list, {:ok, nil}, fn text, _acc ->
      case Validation.validate_string(text, max_length: Validation.max_input_length()) do
        {:ok, _} -> {:cont, {:ok, nil}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_texts(_params), do: {:error, :texts_required}

  defp sanitize_error_for_user(error) when is_struct(error) do
    Sanitize.sanitize_error_message(error)
  end

  defp sanitize_error_for_user(error) when is_atom(error) do
    Sanitize.sanitize_error_message(error)
  end

  defp sanitize_error_for_user(_error), do: "An error occurred"

  defp apply_context_defaults(params, context) when is_map(params) do
    context = normalize_context(context)
    provided = provided_params(context)

    model_default =
      first_present([
        context[:default_model],
        context[:model],
        plugin_default(context, :default_model)
      ])

    put_default_param(params, :model, model_default, provided)
  end

  defp apply_context_defaults(params, _context), do: params

  defp put_default_param(params, _key, nil, _provided), do: params

  defp put_default_param(params, key, default, :unknown) do
    if Map.get(params, key) in [nil, ""] do
      Map.put(params, key, default)
    else
      params
    end
  end

  defp put_default_param(params, key, default, provided) do
    if provided_param?(provided, key) do
      params
    else
      Map.put(params, key, default)
    end
  end

  defp provided_params(%{provided_params: provided}) when is_list(provided), do: provided
  defp provided_params(_), do: :unknown

  defp provided_param?(provided, key) when is_list(provided) do
    key_str = Atom.to_string(key)
    Enum.any?(provided, fn k -> k == key or k == key_str end)
  end

  defp plugin_default(context, key) do
    first_present([
      get_in(context, [:plugin_state, :chat, key]),
      get_in(context, [:plugin_state, :llm, key]),
      get_in(context, [:state, :chat, key]),
      get_in(context, [:state, :llm, key]),
      get_in(context, [:agent, :state, :chat, key]),
      get_in(context, [:agent, :state, :llm, key])
    ])
  end

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))
  defp normalize_context(context) when is_map(context), do: context
  defp normalize_context(_), do: %{}

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
