defmodule Jido.AI.Schemas.ChatResponseSchema do
  @moduledoc """
  Schema for simple chat responses from LLMs.

  This schema validates responses that contain a single text field,
  suitable for natural language assistant responses.

  ## Fields

  - `response` (string, required) - The natural language response from the AI
  """

  use Jido.AI.Schema

  defschema "A chat response from an AI assistant." do
    field(:response, :string,
      required: true,
      doc: "The natural language response text"
    )
  end
end
