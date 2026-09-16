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
    schema:
      Zoi.object(%{
        model:
          Zoi.any(description: "Model alias (e.g., :embedding) or direct model spec string")
          |> Zoi.optional(),
        texts: Zoi.string(description: "Single text to embed") |> Zoi.optional(),
        texts_list:
          Zoi.list(Zoi.string(),
            description: "List of texts to embed (alternative to single text)"
          )
          |> Zoi.optional(),
        dimensions:
          Zoi.integer(description: "Output dimensions for models that support it")
          |> Zoi.optional(),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional()
      })

  @doc "Returns the Action category."
  def category, do: "ai"

  @doc "Returns tags that classify this Action."
  def tags, do: ["llm", "embedding", "vectors"]
  @doc "Returns the Action metadata version."
  def vsn, do: "1.0.0"

  @impl Jido.Action
  def on_before_validate_params(params), do: Jido.AI.ActionInput.before_validate(schema(), params)

  @impl Jido.Action
  def run(params, context),
    do: Jido.AI.Actions.LLM.Request.run(:embed, __MODULE__, params, context)
end
