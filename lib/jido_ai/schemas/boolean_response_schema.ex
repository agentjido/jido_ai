defmodule Jido.AI.Schemas.BooleanResponseSchema do
  @moduledoc """
  Schema for boolean (yes/no) responses with explanation and confidence.

  This schema validates responses for questions that require a true/false answer,
  including reasoning, confidence scoring, and ambiguity detection.

  ## Fields

  - `answer` (boolean, required) - The true/false answer
  - `explanation` (string, required) - Reasoning behind the answer
  - `confidence` (float, required) - Confidence score between 0.0 and 1.0
  - `is_ambiguous` (boolean, required) - Whether the question is ambiguous
  """

  use Jido.AI.Schema

  defschema "A boolean response from an AI assistant with explanation and confidence." do
    field(:answer, :boolean,
      required: true,
      doc: "The true or false answer to the question"
    )

    field(:explanation, :string,
      required: true,
      doc: "A brief explanation of the reasoning behind the answer"
    )

    field(:confidence, :float,
      required: true,
      doc: "Confidence score between 0.0 and 1.0 indicating certainty"
    )

    field(:is_ambiguous, :boolean,
      required: true,
      doc: "Whether the question is ambiguous or unclear"
    )
  end
end
