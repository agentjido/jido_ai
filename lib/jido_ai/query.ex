defmodule Jido.AI.Query do
  @moduledoc "Shared schema and helpers for text or multimodal user queries."

  alias ReqLLM.Message.ContentPart

  @type t :: String.t() | [ContentPart.t()]

  @doc "Returns a Zoi schema that accepts text or a non-empty list of ReqLLM content parts."
  @spec schema(keyword()) :: Zoi.schema()
  def schema(opts \\ []) do
    description = Keyword.get(opts, :description, "User query or multimodal content parts")

    Zoi.union(
      [
        Zoi.string(description: description),
        Zoi.list(Zoi.any(), description: description)
        |> Zoi.refine({__MODULE__, :validate_content_parts, []})
      ],
      opts
    )
  end

  @doc "Validates that a parsed multimodal query is a non-empty list of content parts."
  @spec validate_content_parts(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_content_parts([_ | _] = parts, _opts) do
    if Enum.all?(parts, &content_part?/1) do
      :ok
    else
      {:error, "query content must be a non-empty list of ReqLLM content parts"}
    end
  end

  def validate_content_parts(_parts, _opts),
    do: {:error, "query content must be a non-empty list of ReqLLM content parts"}

  @doc "Returns true when a term is a ReqLLM content part or compatible content-part map."
  @spec content_part?(term()) :: boolean()
  def content_part?(%ContentPart{}), do: true

  def content_part?(%{type: type}) when type in [:text, :image, :image_url, :thinking], do: true
  def content_part?(%{"type" => type}) when type in ["text", "image", "image_url", "thinking"], do: true
  def content_part?(_part), do: false

  @doc "Builds a text summary for event metadata without discarding the original query."
  @spec summarize(t()) :: String.t()
  def summarize(query) when is_binary(query), do: query

  def summarize(parts) when is_list(parts) do
    Enum.map_join(parts, "\n", fn
      %ContentPart{type: :text, text: text} when is_binary(text) -> text
      %ContentPart{type: type} when type in [:image, :image_url] -> "[Image]"
      %{type: type, text: text} when type in [:text, "text"] and is_binary(text) -> text
      %{type: type} when type in [:image, :image_url, "image", "image_url"] -> "[Image]"
      %{"type" => type, "text" => text} when type == "text" and is_binary(text) -> text
      %{"type" => type} when type in ["image", "image_url"] -> "[Image]"
      part -> inspect(part)
    end)
  end
end
