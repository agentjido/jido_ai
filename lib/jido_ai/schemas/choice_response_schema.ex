defmodule Jido.AI.Schemas.ChoiceResponseSchema do
  @moduledoc """
  Schema for multiple choice responses with explanation and confidence.

  This schema validates responses where the AI must select one option
  from a list of available choices and explain its reasoning.

  ## Fields

  - `selected_option` (string, required) - The ID of the chosen option
  - `explanation` (string, required) - Reasoning behind the choice
  - `confidence` (float, required) - Confidence score between 0.0 and 1.0
  """

  use Jido.AI.Schema

  defschema "A response that chooses one of the available options and explains why." do
    field(:selected_option, :string,
      required: true,
      doc: "The ID of the selected option from the available choices"
    )

    field(:explanation, :string,
      required: true,
      doc: "A brief explanation of why this option was chosen"
    )

    field(:confidence, :float,
      required: true,
      doc: "Confidence score between 0.0 and 1.0 indicating certainty of the choice"
    )
  end
end
