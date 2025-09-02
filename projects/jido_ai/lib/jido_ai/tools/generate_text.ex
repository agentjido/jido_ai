defmodule Jido.Tools.AI.GenerateText do
  @moduledoc """
  Generates text using AI models with full validation and error handling.

  Simple action wrapper around Jido.AI.generate_text/3 that provides
  validated parameters and structured responses.

  ## Parameters

  - `:messages` (required) - Text prompt or list of Message structs
  - `:model` - AI model specification (default: "openai:gpt-4o")
  - `:temperature` - Temperature for randomness (0.0-2.0)
  - `:max_tokens` - Maximum tokens to generate
  - `:system_prompt` - Optional system prompt
  - `:actions` - List of Jido Action modules for tools

  ## Examples

      # Basic usage
      {:ok, result} = Jido.Exec.run(GenerateText, %{messages: "Hello world"})
      result.response  #=> "Hello! How can I help you today?"

      # With actions
      {:ok, result} = Jido.Exec.run(GenerateText, %{
        messages: "What's 5 + 3?",
        actions: [Calculator]
      })
  """

  use Jido.Action,
    name: "generate_text",
    description: "Generates text using AI models",
    schema: [
      messages: [
        type: :any,
        required: true,
        doc: "Text prompt or list of Message structs"
      ],
      # Validated by Jido.AI.Messages.validate/1 in generate_text
      model: [
        type: :string,
        default: "openai:gpt-4o",
        doc: "AI model specification"
      ],
      temperature: [
        type: {:custom, Jido.AI.Util, :validate_temperature, []},
        doc: "Temperature for randomness (0.0-2.0)"
      ],
      max_tokens: [
        type: :pos_integer,
        doc: "Maximum tokens to generate"
      ],
      system_prompt: [
        type: {:or, [:string, nil]},
        doc: "Optional system prompt"
      ],
      actions: [
        type: {:custom, Jido.Util, :validate_actions, []},
        default: [],
        doc: "List of Jido Action modules for tools"
      ]
    ]

  import Jido.AI.Util, only: [maybe_put: 3]

  # Override macro-generated specs to match actual implementation
  @spec on_before_validate_params(map()) :: {:ok, map()}
  @spec on_after_validate_params(map()) :: {:ok, map()}
  @spec on_before_validate_output(map()) :: {:ok, map()}
  @spec on_after_validate_output(map()) :: {:ok, map()}
  @spec on_after_run({:ok, map()} | {:error, any()}) :: {:ok, {:ok, map()} | {:error, any()}}
  @spec on_error(map(), any(), map(), keyword()) :: {:ok, map()}

  @impl true
  @spec run(map(), map()) :: {:ok, map()} | {:error, term()}
  def run(%{messages: messages, model: model} = params, _ctx) do
    # Build options from parameters
    opts =
      []
      |> maybe_put(:temperature, Map.get(params, :temperature))
      |> maybe_put(:max_tokens, Map.get(params, :max_tokens))
      |> maybe_put(:system_prompt, Map.get(params, :system_prompt))
      |> maybe_put(:actions, Map.get(params, :actions, []))

    with {:ok, response} <- Jido.AI.generate_text(model, messages, opts) do
      {:ok, Map.put(params, :response, response)}
    end
  end
end
